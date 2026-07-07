FROM node:18-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install --production

FROM node:18-alpine AS runtime
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY server.js ./
EXPOSE 3001
CMD ["node", "server.js"]
