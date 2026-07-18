FROM node:20-bookworm-slim

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY src ./src
COPY data ./data

ENV NODE_ENV=production
EXPOSE 3000

CMD ["npm", "start"]
