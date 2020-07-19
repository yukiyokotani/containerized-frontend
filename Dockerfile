FROM node:current-slim as react-build

WORKDIR /app
COPY package.json /app/
RUN npm install

# EXPOSE 3000
# CMD [ "npm", "start" ]

COPY ./ /app/
RUN npm run build


# Stage 1
# FROM node:8 as react-build
# WORKDIR /app
# COPY . ./
# RUN yarn
# RUN yarn build

# Stage 2 - the production environment
FROM nginx:1.19.1-alpine
# COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=react-build /app/build /var/www
COPY --from=react-build /app/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]