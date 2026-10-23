import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const script = fs.readFileSync(process.argv[2], 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];

// Only the DOM surface used by the local canvas is modeled. This checks the
// shipped camera/input code, not browser layout, GPU caching or Android FPS.
function canvas(options = {}) {
  let now = 0;
  let nextId = 1;
  let resize;
  const frames = new Map();
  const timers = new Map();
  const messages = [];
  const writes = [];
  const viewport = {left: 0, top: 0, width: 390, height: 700};
  let bboxReads = 0;
  let rectReads = 0;

  class Element {
    constructor(name, attributes = {}) {
      this.localName = name;
      this.attrs = Object.fromEntries(Object.entries(attributes).map(([name, value]) => [name, String(value)]));
      this.children = [];
      this.parentNode = null;
      this.dataset = {};
      this.style = {
        setProperty(name, value) { this[name] = value; },
        getPropertyValue(name) { return this[name] || ''; },
      };
      this.listeners = new Map();
    }
    get id() { return this.attrs.id; }
    set id(value) { this.attrs.id = value; }
    get attributes() { return Object.entries(this.attrs).map(([name, value]) => ({name, value})); }
    setAttribute(name, value) { this.attrs[name] = String(value); writes.push({element: this, name, value: String(value)}); }
    getAttribute(name) { return this.attrs[name] ?? null; }
    removeAttribute(name) { delete this.attrs[name]; }
    appendChild(child) { child.parentNode = this; this.children.push(child); return child; }
    append(...children) { children.forEach(child => this.appendChild(child)); }
    replaceChildren(...children) { this.children = []; this.append(...children); }
    remove() { this.parentNode.children = this.parentNode.children.filter(child => child !== this); }
    querySelectorAll(selector) {
      const descendants = this.children.flatMap(child => [child, ...child.querySelectorAll('*')]);
      if (selector === '*') return descendants;
      if (selector === '[id]') return descendants.filter(child => child.id);
      return descendants.filter(child => selector.split(/,\s*/).includes(child.localName));
    }
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
    closest(selector) {
      if (selector === '[data-place-id]' && this.dataset.placeId) return this;
      return this.parentNode?.closest(selector) || null;
    }
    cloneNode(deep) {
      const clone = new Element(this.localName, this.attrs);
      clone.dataset = {...this.dataset};
      if (deep) clone.append(...this.children.map(child => child.cloneNode(true)));
      return clone;
    }
    getBBox() {
      bboxReads++;
      if (this.localName === 'rect') return {
        x: Number(this.attrs.x), y: Number(this.attrs.y),
        width: Number(this.attrs.width), height: Number(this.attrs.height),
      };
      const boxes = this.children.map(child => child.getBBox());
      if (!boxes.length) return {x: 0, y: 0, width: 0, height: 0};
      const x = Math.min(...boxes.map(box => box.x));
      const y = Math.min(...boxes.map(box => box.y));
      return {x, y, width: Math.max(...boxes.map(box => box.x + box.width)) - x,
        height: Math.max(...boxes.map(box => box.y + box.height)) - y};
    }
    getBoundingClientRect() { rectReads++; return {...viewport}; }
    get clientWidth() { return viewport.width; }
    get clientHeight() { return viewport.height; }
    addEventListener(type, callback) { this.listeners.set(type, callback); }
    setPointerCapture() {}
  }

  const host = new Element('div', {id: 'map'});
  const document = {
    documentElement: new Element('html'), body: new Element('body'), hidden: false,
    getElementById(id) { return id === 'map' ? host : host.querySelectorAll('[id]').find(child => child.id === id); },
    createElement: name => new Element(name),
    createElementNS: (_, name) => new Element(name),
    importNode: (element, deep) => element.cloneNode(deep),
    elementsFromPoint: () => [],
    listeners: new Map(),
    addEventListener(type, callback) { this.listeners.set(type, callback); },
  };
  const source = new Element('svg');
  source.append(new Element('rect', {id: 'building', x: 180, y: 180, width: 40, height: 30}));
  const window = {ShuyoMap: {postMessage: value => messages.push(JSON.parse(value))},
    matchMedia: () => ({matches: options.reducedMotion === true})};
  vm.runInNewContext(script, {
    window, document, performance: {now: () => now},
    Date: class extends Date { static now() { return now; } },
    DOMParser: class { parseFromString() { return {documentElement: source.cloneNode(true)}; } },
    ResizeObserver: class { constructor(callback) { resize = callback; } observe() {} },
    requestAnimationFrame(callback) { const id = nextId++; frames.set(id, callback); return id; },
    cancelAnimationFrame(id) { frames.delete(id); },
    setTimeout(callback, delay) { const id = nextId++; timers.set(id, {callback, at: now + delay}); return id; },
    clearTimeout(id) { timers.delete(id); },
  });

  const config = {campusId: 'test', svg: '<svg/>', viewBox: [0, 0, 1000, 1000],
    initialView: {center: {x: 200, y: 200}, zoom: 2}, backgroundColor: '#eaeadf', debug: false,
    places: [{id: 'building', featureIds: ['building'], point: {x: 200, y: 195}},
      {id: 'point', featureIds: [], point: {x: 250, y: 250}}], bottomInset: 0,
    cachedGestures: options.cachedGestures !== false};
  function tick(ms = 1000 / 60) {
    now += ms;
    const callbacks = [...frames.values()]; frames.clear();
    callbacks.forEach(callback => callback(now));
    for (const [id, timer] of timers) if (timer.at <= now) { timers.delete(id); timer.callback(); }
  }
  function settle() {
    for (let i = 0; frames.size && i < 180; i++) tick();
    assert.equal(frames.size, 0, 'camera must settle');
  }
  function pointer(type, x, y, id = 1) {
    host.listeners.get(type)({clientX: x + viewport.left, clientY: y + viewport.top,
      pointerId: id, timeStamp: now, preventDefault() {}});
  }
  function update(data = {}) { window.campusMap.update({selectedId: null, location: null,
    accent: '#3478d4', bottomInset: 0, focus: false, focusPoint: null, ...data}); }
  function box(element) {
    const [x, y, width, height] = element.getAttribute('viewBox').split(/\s+/).map(Number);
    return {x, y, width, height};
  }
  const base = () => document.getElementById('map-base');
  const overlay = () => document.getElementById('map-overlay');
  function screen(point, view = box(overlay())) { return {
    x: (point.x - view.x) * viewport.width / view.width,
    y: (point.y - view.y) * viewport.height / view.height,
  }; }
  function checkAlignment(point = {x: 200, y: 195}) {
    const layer = base(); const map = layer.children[0]; const bounds = box(map);
    const match = layer.style.transform?.match(/matrix\(([^)]+)\)/);
    const [sx, , , sy, tx, ty] = match ? match[1].split(',').map(Number) : [1, 0, 0, 1, 0, 0];
    const actual = {x: (point.x - bounds.x) / bounds.width * parseFloat(layer.style.width) * sx + tx,
      y: (point.y - bounds.y) / bounds.height * parseFloat(layer.style.height) * sy + ty};
    const expected = screen(point);
    near(actual.x, expected.x); near(actual.y, expected.y);
  }
  window.campusMap.load(config); tick();
  assert.ok(!messages.some(message => message.type === 'error'), 'fixture must load');
  return {host, document, window, config, viewport, frames, messages, writes,
    base, overlay, box, screen, tick, settle, pointer, update, checkAlignment,
    resize(width, height) { viewport.width = width; viewport.height = height; resize(); },
    advance(ms) { now += ms; },
    get reads() { return {bbox: bboxReads, rect: rectReads}; },
  };
}

function near(actual, expected, epsilon = 1e-6) {
  assert.ok(Math.abs(actual - expected) <= epsilon, `${actual} must be close to ${expected}`);
}

const cases = [];
function test(name, run) { cases.push({name, run}); }

test('short drags transform the retained base and keep overlay coordinates aligned', () => {
  const c = canvas(); const map = c.base().children[0]; const initial = map.getAttribute('viewBox');
  const before = c.reads;
  c.pointer('pointerdown', 190, 350);
  for (let i = 1; i <= 4; i++) {
    c.pointer('pointermove', 190 + i * 5, 350 + i * 2); c.tick();
    assert.equal(map.getAttribute('viewBox'), initial);
    c.checkAlignment();
  }
  assert.equal(c.reads.bbox, before.bbox);
  assert.equal(c.reads.rect, before.rect + 1);
  c.pointer('pointerup', 210, 358); c.settle(); c.checkAlignment();
});

test('long drags refresh overscan before the viewport leaves the cached map', () => {
  const c = canvas(); const map = c.base().children[0]; const initial = map.getAttribute('viewBox');
  c.pointer('pointerdown', 100, 350); c.pointer('pointermove', 300, 350); c.tick();
  assert.notEqual(map.getAttribute('viewBox'), initial); c.checkAlignment();
});

test('pinch zoom keeps the midpoint anchored and refreshes excessive cache scaling', () => {
  const c = canvas(); const anchor = c.screen({x: 200, y: 200});
  c.pointer('pointerdown', anchor.x - 40, anchor.y, 1);
  c.pointer('pointerdown', anchor.x + 40, anchor.y, 2);
  c.pointer('pointermove', anchor.x - 80, anchor.y, 1);
  c.pointer('pointermove', anchor.x + 80, anchor.y, 2); c.tick();
  near(c.screen({x: 200, y: 200}).x, anchor.x);
  near(c.screen({x: 200, y: 200}).y, anchor.y); c.checkAlignment();
});

test('selection is isolated from the cached SVG and marker nodes are retained', () => {
  const c = canvas(); const map = c.base().children[0];
  c.update({selectedId: 'building'}); c.tick();
  const selection = c.overlay().children[0];
  assert.equal(selection.children.length, 1);
  assert.equal(selection.children[0].getAttribute('id'), null);
  assert.equal(map.children[0].getAttribute('class'), null);
  const markers = [...c.overlay().children[1].children];
  c.pointer('pointerdown', 190, 350); c.pointer('pointermove', 210, 350); c.tick();
  assert.deepEqual(c.overlay().children[1].children, markers);
});

test('keyboard and panel resizing preserve the focus center across layers', () => {
  const c = canvas();
  c.update({selectedId: 'building', bottomInset: 210, focus: true}); c.tick(80);
  c.resize(390, 400); c.tick(); c.resize(390, 700);
  c.update({selectedId: 'building', bottomInset: 280}); c.settle();
  const selected = c.screen({x: 200, y: 195});
  near(selected.x, 195); near(selected.y, 210); c.checkAlignment();
});

test('disabled caching retains direct SVG updates and handles viewport resizing', () => {
  const c = canvas({cachedGestures: false}); const map = c.base().children[0];
  const initial = map.getAttribute('viewBox');
  c.pointer('pointerdown', 190, 350); c.pointer('pointermove', 210, 350); c.tick();
  assert.notEqual(map.getAttribute('viewBox'), initial); c.checkAlignment();
  c.resize(700, 390); c.tick(); c.checkAlignment();
  assert.equal(c.base().style.willChange, undefined);
});

test('switching campuses discards the old layer and pending frames', () => {
  const c = canvas(); const old = c.base();
  c.pointer('pointerdown', 190, 350); c.pointer('pointermove', 210, 350);
  c.window.campusMap.load({...c.config, campusId: 'another', initialView: {center: {x: 300, y: 300}, zoom: 1}});
  c.settle(); assert.notEqual(c.base(), old); c.checkAlignment();
  const current = c.box(c.overlay()); near(current.x + current.width / 2, 300);
});

let failed = 0;
for (const {name, run} of cases) {
  try { run(); process.stdout.write(`PASS ${name}\n`); }
  catch (error) { failed++; process.stderr.write(`FAIL ${name}\n${error.stack}\n`); }
}
if (failed) process.exitCode = 1;
