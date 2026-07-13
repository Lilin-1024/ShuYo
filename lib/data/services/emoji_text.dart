import 'package:flutter/widgets.dart';

class EmojiEntry {
  const EmojiEntry(this.shortcode, this.value);

  final String shortcode;
  final String value;

  String get markup => ':$shortcode:';
}

class EmojiCategory {
  const EmojiCategory(this.label, this.entries);

  final String label;
  final List<EmojiEntry> entries;
}

class EmojiText {
  const EmojiText._();

  static const categories = <EmojiCategory>[
    EmojiCategory('常用', [
      EmojiEntry('smile', '\u{1F604}'),
      EmojiEntry('joy', '\u{1F602}'),
      EmojiEntry('sob', '\u{1F62D}'),
      EmojiEntry('thinking', '\u{1F914}'),
      EmojiEntry('heart', '\u{2764}\u{FE0F}'),
      EmojiEntry('thumbsup', '\u{1F44D}'),
      EmojiEntry('clap', '\u{1F44F}'),
      EmojiEntry('wave', '\u{1F44B}'),
      EmojiEntry('fire', '\u{1F525}'),
      EmojiEntry('tada', '\u{1F389}'),
      EmojiEntry('gift', '\u{1F381}'),
      EmojiEntry('student', '\u{1F9D1}\u{200D}\u{1F393}'),
      EmojiEntry('coffee', '\u{2615}'),
      EmojiEntry('book', '\u{1F4D6}'),
      EmojiEntry('warning', '\u{26A0}\u{FE0F}'),
    ]),
    EmojiCategory('笑脸和情感', [
      EmojiEntry('grinning', '\u{1F600}'),
      EmojiEntry('grin', '\u{1F601}'),
      EmojiEntry('smiley', '\u{1F603}'),
      EmojiEntry('smile', '\u{1F604}'),
      EmojiEntry('laughing', '\u{1F606}'),
      EmojiEntry('sweat_smile', '\u{1F605}'),
      EmojiEntry('joy', '\u{1F602}'),
      EmojiEntry('rofl', '\u{1F923}'),
      EmojiEntry('slight_smile', '\u{1F642}'),
      EmojiEntry('upside_down_face', '\u{1F643}'),
      EmojiEntry('wink', '\u{1F609}'),
      EmojiEntry('blush', '\u{1F60A}'),
      EmojiEntry('innocent', '\u{1F607}'),
      EmojiEntry('relaxed', '\u{263A}\u{FE0F}'),
      EmojiEntry('heart_eyes', '\u{1F60D}'),
      EmojiEntry('star_struck', '\u{1F929}'),
      EmojiEntry('kissing_heart', '\u{1F618}'),
      EmojiEntry('kissing_face', '\u{1F617}'),
      EmojiEntry('kissing_smiling_eyes', '\u{1F619}'),
      EmojiEntry('yum', '\u{1F60B}'),
      EmojiEntry('stuck_out_tongue', '\u{1F61B}'),
      EmojiEntry('stuck_out_tongue_winking_eye', '\u{1F61C}'),
      EmojiEntry('sunglasses', '\u{1F60E}'),
      EmojiEntry('partying_face', '\u{1F973}'),
      EmojiEntry('hugging_face', '\u{1F917}'),
      EmojiEntry('thinking', '\u{1F914}'),
      EmojiEntry('shushing_face', '\u{1F92B}'),
      EmojiEntry('neutral_face', '\u{1F610}'),
      EmojiEntry('expressionless', '\u{1F611}'),
      EmojiEntry('rolling_eyes', '\u{1F644}'),
      EmojiEntry('smirk', '\u{1F60F}'),
      EmojiEntry('pensive', '\u{1F614}'),
      EmojiEntry('relieved', '\u{1F60C}'),
      EmojiEntry('sleepy', '\u{1F62A}'),
      EmojiEntry('sleeping', '\u{1F634}'),
      EmojiEntry('drooling_face', '\u{1F924}'),
      EmojiEntry('mask', '\u{1F637}'),
      EmojiEntry('flushed', '\u{1F633}'),
      EmojiEntry('confused', '\u{1F615}'),
      EmojiEntry('worried', '\u{1F61F}'),
      EmojiEntry('cry', '\u{1F622}'),
      EmojiEntry('sob', '\u{1F62D}'),
      EmojiEntry('scream', '\u{1F631}'),
      EmojiEntry('angry', '\u{1F620}'),
      EmojiEntry('rage', '\u{1F621}'),
      EmojiEntry('dizzy_face', '\u{1F635}'),
      EmojiEntry('exploding_head', '\u{1F92F}'),
      EmojiEntry('smiling_imp', '\u{1F608}'),
      EmojiEntry('imp', '\u{1F47F}'),
      EmojiEntry('skull', '\u{1F480}'),
      EmojiEntry('poop', '\u{1F4A9}'),
    ]),
    EmojiCategory('人和身体', [
      EmojiEntry('wave', '\u{1F44B}'),
      EmojiEntry('raised_hand', '\u{270B}'),
      EmojiEntry('v', '\u{270C}\u{FE0F}'),
      EmojiEntry('crossed_fingers', '\u{1F91E}'),
      EmojiEntry('metal', '\u{1F918}'),
      EmojiEntry('call_me_hand', '\u{1F919}'),
      EmojiEntry('ok_hand', '\u{1F44C}'),
      EmojiEntry('pinching_hand', '\u{1F90F}'),
      EmojiEntry('point_left', '\u{1F448}'),
      EmojiEntry('point_right', '\u{1F449}'),
      EmojiEntry('point_up_2', '\u{1F446}'),
      EmojiEntry('point_down', '\u{1F447}'),
      EmojiEntry('thumbsup', '\u{1F44D}'),
      EmojiEntry('thumbsdown', '\u{1F44E}'),
      EmojiEntry('clap', '\u{1F44F}'),
      EmojiEntry('pray', '\u{1F64F}'),
      EmojiEntry('muscle', '\u{1F4AA}'),
      EmojiEntry('writing_hand', '\u{270D}\u{FE0F}'),
      EmojiEntry('eyes', '\u{1F440}'),
      EmojiEntry('person', '\u{1F9D1}'),
      EmojiEntry('man', '\u{1F468}'),
      EmojiEntry('woman', '\u{1F469}'),
      EmojiEntry('student', '\u{1F9D1}\u{200D}\u{1F393}'),
      EmojiEntry('man_student', '\u{1F468}\u{200D}\u{1F393}'),
      EmojiEntry('woman_student', '\u{1F469}\u{200D}\u{1F393}'),
      EmojiEntry('teacher', '\u{1F9D1}\u{200D}\u{1F3EB}'),
      EmojiEntry('man_teacher', '\u{1F468}\u{200D}\u{1F3EB}'),
      EmojiEntry('woman_teacher', '\u{1F469}\u{200D}\u{1F3EB}'),
      EmojiEntry('older_adult', '\u{1F9D3}'),
      EmojiEntry('baby', '\u{1F476}'),
      EmojiEntry('boy', '\u{1F466}'),
      EmojiEntry('girl', '\u{1F467}'),
    ]),
    EmojiCategory('动物和自然', [
      EmojiEntry('dog', '\u{1F436}'),
      EmojiEntry('cat', '\u{1F431}'),
      EmojiEntry('mouse_face', '\u{1F42D}'),
      EmojiEntry('hamster', '\u{1F439}'),
      EmojiEntry('rabbit', '\u{1F430}'),
      EmojiEntry('fox_face', '\u{1F98A}'),
      EmojiEntry('bear', '\u{1F43B}'),
      EmojiEntry('panda_face', '\u{1F43C}'),
      EmojiEntry('koala', '\u{1F428}'),
      EmojiEntry('tiger', '\u{1F42F}'),
      EmojiEntry('lion', '\u{1F981}'),
      EmojiEntry('cow', '\u{1F42E}'),
      EmojiEntry('pig', '\u{1F437}'),
      EmojiEntry('frog', '\u{1F438}'),
      EmojiEntry('monkey_face', '\u{1F435}'),
      EmojiEntry('chicken', '\u{1F414}'),
      EmojiEntry('penguin', '\u{1F427}'),
      EmojiEntry('bird', '\u{1F426}'),
      EmojiEntry('turtle', '\u{1F422}'),
      EmojiEntry('fish', '\u{1F41F}'),
      EmojiEntry('butterfly', '\u{1F98B}'),
      EmojiEntry('seedling', '\u{1F331}'),
      EmojiEntry('herb', '\u{1F33F}'),
      EmojiEntry('rose', '\u{1F339}'),
      EmojiEntry('sunflower', '\u{1F33B}'),
      EmojiEntry('blossom', '\u{1F33C}'),
    ]),
    EmojiCategory('食物', [
      EmojiEntry('apple', '\u{1F34E}'),
      EmojiEntry('tangerine', '\u{1F34A}'),
      EmojiEntry('lemon', '\u{1F34B}'),
      EmojiEntry('banana', '\u{1F34C}'),
      EmojiEntry('watermelon', '\u{1F349}'),
      EmojiEntry('grapes', '\u{1F347}'),
      EmojiEntry('strawberry', '\u{1F353}'),
      EmojiEntry('bread', '\u{1F35E}'),
      EmojiEntry('cheese', '\u{1F9C0}'),
      EmojiEntry('egg', '\u{1F95A}'),
      EmojiEntry('hamburger', '\u{1F354}'),
      EmojiEntry('fries', '\u{1F35F}'),
      EmojiEntry('pizza', '\u{1F355}'),
      EmojiEntry('ramen', '\u{1F35C}'),
      EmojiEntry('rice', '\u{1F35A}'),
      EmojiEntry('cake', '\u{1F370}'),
      EmojiEntry('birthday', '\u{1F382}'),
      EmojiEntry('candy', '\u{1F36C}'),
      EmojiEntry('tea', '\u{1F375}'),
      EmojiEntry('coffee', '\u{2615}'),
      EmojiEntry('beer', '\u{1F37A}'),
    ]),
    EmojiCategory('活动', [
      EmojiEntry('soccer', '\u{26BD}'),
      EmojiEntry('basketball', '\u{1F3C0}'),
      EmojiEntry('football', '\u{1F3C8}'),
      EmojiEntry('tennis', '\u{1F3BE}'),
      EmojiEntry('volleyball', '\u{1F3D0}'),
      EmojiEntry('ping_pong', '\u{1F3D3}'),
      EmojiEntry('badminton', '\u{1F3F8}'),
      EmojiEntry('trophy', '\u{1F3C6}'),
      EmojiEntry('medal_sports', '\u{1F3C5}'),
      EmojiEntry('video_game', '\u{1F3AE}'),
      EmojiEntry('art', '\u{1F3A8}'),
      EmojiEntry('microphone', '\u{1F3A4}'),
      EmojiEntry('headphones', '\u{1F3A7}'),
      EmojiEntry('musical_note', '\u{1F3B5}'),
      EmojiEntry('guitar', '\u{1F3B8}'),
      EmojiEntry('tada', '\u{1F389}'),
    ]),
    EmojiCategory('物品', [
      EmojiEntry('iphone', '\u{1F4F1}'),
      EmojiEntry('telephone', '\u{260E}\u{FE0F}'),
      EmojiEntry('computer', '\u{1F4BB}'),
      EmojiEntry('desktop_computer', '\u{1F5A5}\u{FE0F}'),
      EmojiEntry('keyboard', '\u{2328}\u{FE0F}'),
      EmojiEntry('camera', '\u{1F4F7}'),
      EmojiEntry('video_camera', '\u{1F4F9}'),
      EmojiEntry('bulb', '\u{1F4A1}'),
      EmojiEntry('book', '\u{1F4D6}'),
      EmojiEntry('books', '\u{1F4DA}'),
      EmojiEntry('mortar_board', '\u{1F393}'),
      EmojiEntry('pencil2', '\u{270F}\u{FE0F}'),
      EmojiEntry('memo', '\u{1F4DD}'),
      EmojiEntry('pushpin', '\u{1F4CC}'),
      EmojiEntry('paperclip', '\u{1F4CE}'),
      EmojiEntry('link', '\u{1F517}'),
      EmojiEntry('lock', '\u{1F512}'),
      EmojiEntry('key', '\u{1F511}'),
      EmojiEntry('gift', '\u{1F381}'),
      EmojiEntry('envelope', '\u{2709}\u{FE0F}'),
      EmojiEntry('bell', '\u{1F514}'),
      EmojiEntry('hourglass', '\u{231B}'),
      EmojiEntry('alarm_clock', '\u{23F0}'),
      EmojiEntry('calendar', '\u{1F4C5}'),
    ]),
    EmojiCategory('符号', [
      EmojiEntry('heart', '\u{2764}\u{FE0F}'),
      EmojiEntry('orange_heart', '\u{1F9E1}'),
      EmojiEntry('yellow_heart', '\u{1F49B}'),
      EmojiEntry('green_heart', '\u{1F49A}'),
      EmojiEntry('blue_heart', '\u{1F499}'),
      EmojiEntry('purple_heart', '\u{1F49C}'),
      EmojiEntry('broken_heart', '\u{1F494}'),
      EmojiEntry('100', '\u{1F4AF}'),
      EmojiEntry('sparkles', '\u{2728}'),
      EmojiEntry('star', '\u{2B50}'),
      EmojiEntry('white_check_mark', '\u{2705}'),
      EmojiEntry('heavy_check_mark', '\u{2714}\u{FE0F}'),
      EmojiEntry('x', '\u{274C}'),
      EmojiEntry('heavy_multiplication_x', '\u{2716}\u{FE0F}'),
      EmojiEntry('question', '\u{2753}'),
      EmojiEntry('grey_question', '\u{2754}'),
      EmojiEntry('exclamation', '\u{2757}'),
      EmojiEntry('grey_exclamation', '\u{2755}'),
      EmojiEntry('warning', '\u{26A0}\u{FE0F}'),
      EmojiEntry('recycle', '\u{267B}\u{FE0F}'),
      EmojiEntry('arrow_up', '\u{2B06}\u{FE0F}'),
      EmojiEntry('arrow_down', '\u{2B07}\u{FE0F}'),
      EmojiEntry('arrow_left', '\u{2B05}\u{FE0F}'),
      EmojiEntry('arrow_right', '\u{27A1}\u{FE0F}'),
      EmojiEntry('up_right_arrow', '\u{2197}\u{FE0F}'),
    ]),
  ];

  static final entries = <EmojiEntry>[
    for (final category in categories) ...category.entries,
  ];

  static const _aliases = <String, String>{
    '+1': '\u{1F44D}',
    '-1': '\u{1F44E}',
    'satisfied': '\u{1F606}',
    'hugs': '\u{1F917}',
    'frowning': '\u{2639}\u{FE0F}',
    'hand': '\u{270B}',
    'thumbs_up': '\u{1F44D}',
    'thumbs_down': '\u{1F44E}',
    'thumbsdown': '\u{1F44E}',
    'phone': '\u{260E}\u{FE0F}',
    'email': '\u{2709}\u{FE0F}',
    'party_popper': '\u{1F389}',
  };

  static final _map = <String, String>{
    for (final entry in entries) entry.shortcode: entry.value,
    ..._aliases,
  };

  static final _shortcodePattern = RegExp(r':([a-zA-Z0-9_+\-]+):');

  static List<EmojiEntry> entriesForShortcodes(List<String> shortcodes) {
    return [
      for (final shortcode in shortcodes)
        if (_map[shortcode] != null) EmojiEntry(shortcode, _map[shortcode]!),
    ];
  }

  static String render(String value) {
    if (!value.contains(':')) {
      return value;
    }
    return value.replaceAllMapped(_shortcodePattern, (match) {
      final key = match.group(1);
      return key == null ? match.group(0)! : _map[key] ?? match.group(0)!;
    });
  }

  static void insertShortcode(
    TextEditingController controller,
    String shortcode,
  ) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final before = text.substring(0, start);
    final after = text.substring(end);
    final leading =
        before.isEmpty || RegExp(r'\s$').hasMatch(before) ? '' : ' ';
    final trailing = after.isEmpty || RegExp(r'^\s').hasMatch(after) ? '' : ' ';
    final inserted = '$leading:$shortcode:$trailing';
    controller.text = '$before$inserted$after';
    controller.selection = TextSelection.collapsed(
      offset: before.length + inserted.length,
    );
  }
}
