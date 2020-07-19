# React アプリケーションの GCP へのデプロイ

React によるフロントエンドを Docker コンテナ化し、GCP の Cloud Engine 上にデプロイする手順を示す。  
作業の大きな流れは以下の通り。

1. [React によるフロントエンドの作成](##1.-React-によるフロントエンドの作成)
2. [React アプリの Docker コンテナ化](##2.-React-アプリのコンテナ化)
3. [GCP 周りの諸設定](##3.GCP-周りの諸設定)
4. [GCP の Container Registry への Docker Push](##4.-GCP-の-Container-Registry-への-Docker-Push)
5. [GCP へプッシュした Docker コンテナをベースにした VM インスタンスの起動](##5.-GCP-へプッシュした-Docker-コンテナをベースにした-VM-インスタンスの起動)

> 注意：npm や docker, gcloud のインストールについては済んでいるものとして手順を省略する

## 1. React によるフロントエンドの作成

今回は簡単のため、create-react-app で用意される雛形をデプロイする。  
適当な作業ディレクトリにおいて、以下のコマンドでアプリケーションを作成する。  
ここでは `frontend` という名前にした。

```bash
$ npx create-react-app frontend --template typescript
```

## 2. React アプリのコンテナ化

### 2.1 Docker イメージの作成

`/frontend` に `Dockerfile` を作成する。

```bash
$ cd frontend
$ touch Dockerfile
```

`Dockerfile` の中身は以下の通り。

```docker
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
```

`Stage 1` では `Node.js` のコンテナに [1.](##1.Reactによるフロントエンドの作成) で作った React アプリをコピーしビルドする。  
`Stage 2` では `NGINX` のコンテナへ先程ビルドしたファイルをコピーし、port 80 で起動する。

また、ここで `/frontend` に `nginx.conf` も以下の通り作成する。  
この設定は [Deploy your Create React App with Docker and Nginx](https://medium.com/yld-blog/deploy-your-create-react-app-with-docker-and-ngnix-653e94ffb537) を参考にした。

```docker
# auto detects a good number of processes to run
worker_processes auto;

#Provides the configuration file context in which the directives that affect connection processing are specified.
events {
    # Sets the maximum number of simultaneous connections that can be opened by a worker process.
    worker_connections 8000;
    # Tells the worker to accept multiple connections at a time
    multi_accept on;
}


http {
    # what times to include
    include       /etc/nginx/mime.types;
    # what is the default one
    default_type  application/octet-stream;

    # Sets the path, format, and configuration for a buffered log write
    log_format compression '$remote_addr - $remote_user [$time_local] '
        '"$request" $status $upstream_addr '
        '"$http_referer" "$http_user_agent"';

    server {
        # listen on port 80
        listen 80;
        # save logs here
        access_log /var/log/nginx/access.log compression;

        # where the root here
        root /var/www;
        # what file to server as index
        index index.html index.htm;

        location / {
            # First attempt to serve request as file, then
            # as directory, then fall back to redirecting to index.html
            try_files $uri $uri/ /index.html;
        }

        # Media: images, icons, video, audio, HTC
        location ~* \.(?:jpg|jpeg|gif|png|ico|cur|gz|svg|svgz|mp4|ogg|ogv|webm|htc)$ {
          expires 1M;
          access_log off;
          add_header Cache-Control "public";
        }

        # Javascript and CSS files
        location ~* \.(?:css|js)$ {
            try_files $uri =404;
            expires 1y;
            access_log off;
            add_header Cache-Control "public";
        }

        # Any route containing a file extension (e.g. /devicesfile.js)
        location ~ ^.+\..+$ {
            try_files $uri =404;
        }
    }
}
```

以上で React アプリを起動するための Docker イメージが完成したので、以下のコマンドでイメージをビルドする。

```bash
$ docker image build --tag frontend:1.0 .
```

オプションの意味についてはここでは省略する。

### 2.2 Docker コンテナの起動

イメージのビルドが成功したらコンテナが起動できるか確認する。

```bash
$ docker run --rm -d -p 80:80 frontend:1.0
```

ブラウザで http://localhost へアクセスし、create-react-app の雛形が表示されていることを確認する。  
確認が済んだら、コマンド `docker stop [コンテナID]` か、Docker Desktop の Dashboard からコンテナを停止しておく。

## 3. GCP 周りの諸設定

所有している Google アカウントの GCP を有効化し、新規プロジェクトを作成する。  
リージョンやリソースの設定については以下などを参考に、適当に設定する。  
[Qiita - これから始める GCP（GCE）　安全に無料枠を使い倒せ](https://qiita.com/Brutus/items/22dfd31a681b67837a74)

> 一応インスタンスを起動して、確認してすぐに停止、くらいだと請求 0 円なので、  
> ちゃんと停止することを忘れなければ高額請求が来ることはないはず…

また、この先の Container Registry への `Docker push` に必要なので Google Cloud SDK をインストールする。  
インストール手順については以下を参照。  
https://cloud.google.com/sdk/docs/quickstarts?hl=ja

インストールが完了し、CLI で `gcloud` コマンドが使えるようになったら、以下のコマンドで認証しておく。

```
$ gcloud auth configure-docker
```

ブラウザでページが開き、Google アカウントを使った認証を求められるので認証する。

## 4. GCP の Container Registry への Docker Push

ここから先の手順は以下が参考になる。  
[Qiita - docker イメージ を GCE で起動する方法](https://qiita.com/na59ri/items/c540d9d16a1fc1c5a9c4)

まず、[2.](##2.-React-アプリのコンテナ化) で作成した Docker イメージ `frontend:1.0` に、GCP へプッシュするためのタグをつける。

```
$ docker tag frontend:1.0 us.gcr.io/プロジェクトID/frontend
```

ここで、`プロジェクトID` は [3.](##3.GCP-周りの諸設定) で作成したプロジェクトの ID なので、GCP 上で確認し適宜指定する。  
また、最後の `/frontend` のところは GCP 上でのイメージ名なので `frontend` である必要はない。

## 5. GCP へプッシュした Docker コンテナをベースにした VM インスタンスの起動

ここも先程紹介した [Qiita - docker イメージ を GCE で起動する方法](https://qiita.com/na59ri/items/c540d9d16a1fc1c5a9c4) が写真付きでわかりやすいので、ここでは省略する。  
port は 80 なので、記事内で行われているファイアウォールの設定などは不要。

これで、VM インスタンスを起動し、与えられる外部 IP へアクセスすると、create-react-app のひな形が確認できる。  
確認が終わったら、インスタンスの停止を忘れずに行う。
