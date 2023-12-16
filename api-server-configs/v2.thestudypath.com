# Default server configuration
#
server {

        root /home/jantu/frontend/studypath-admin-v2/build;

        server_name v2.thestudypath.com;

        location / {

                try_files $uri  /index.html;

        }


        location /api {
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_pass http://localhost:4000;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection 'upgrade';
                proxy_set_header Host $host;
                proxy_cache_bypass $http_upgrade;

        }




    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/v2.thestudypath.com/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/v2.thestudypath.com/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

}




server {
    if ($host = v2.thestudypath.com) {
        return 301 https://$host$request_uri;
    } # managed by Certbot



    server_name v2.thestudypath.com;
    listen 80;
    return 404; # managed by Certbot


}