# templates/site-advanced.conf.tpl

server {
    server_name ${domain};
    listen      ${port};

%{ if port == 443 ~}
    ssl_certificate     /etc/ssl/certs/${domain}.crt;
    ssl_certificate_key /etc/ssl/private/${domain}.key;
%{ endif ~}

    location / {
        proxy_pass http://127.0.0.1:${app_port};
    }
}
