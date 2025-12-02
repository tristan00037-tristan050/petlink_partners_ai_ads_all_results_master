FROM node:18-alpine

WORKDIR /app

COPY server/mock/package.json ./
RUN npm install

COPY server/mock/index.js ./

EXPOSE 3006

CMD ["node", "index.js"]


