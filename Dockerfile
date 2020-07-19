# Stage 1
FROM node:current-slim as react-build
WORKDIR /app
COPY package.json /app/
RUN npm install
COPY ./ /app/
RUN npm run build

# Stage 2 - the production environment
FROM nginx:1.19.1-alpine
COPY --from=react-build /app/build /var/www
COPY --from=react-build /app/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]