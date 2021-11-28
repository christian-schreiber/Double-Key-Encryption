#ssh -o ServerAliveInterval=60 christian@arch.my365way.com
#Create encrypted Partition
lsblk
sudo cfdisk /dev/sdc
sudo cryptsetup --type luks2 --cipher aes-xts-plain64 --hash sha256 --iter-time 2000 --key-size 256 --use-urandom --verify-passphrase luksFormat /dev/sdc
sudo cryptsetup luksOpen /dev/sdc www
sudo mkfs.ext4 /dev/mapper/www
sudo dd if=/dev/random bs=32 count=1 of=/root/www_key
sudo cryptsetup luksAddKey /dev/sdc /root/www_key
sudo cryptsetup luksDump /dev/sdc
sudo sh -c "echo '/dev/mapper/www         /www    ext4    defaults    0 0' >> /etc/fstab"
sudo sh -c "echo 'www        /dev/sdc     /root/www_key' >> /etc/crypttab"
sudo systemctl daemon-reload
sudo systemctl restart cryptsetup.target
sudo reboot
df -h
#Check Boot Messages
dmesg
#Retrieve the latest mirror list from the Arch Linux Mirror Status
sudo reflector -c Germany --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
sudo pacman -Syyy
#Set NTP
sudo timedatectl set-ntp true
#Set TimeZone
sudo ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
sudo hwclock --systohc
#Edit locale.gen
sudo sed -i '/#en_US.UTF-8/s/^#//g' /etc/locale.gen
sudo locale-gen
sudo sh -c "echo 'LANG=en_US.UTF-8' >> /etc/locale.conf"
sudo sh -c "echo 'LANGUAGE=en_US' >> /etc/locale.conf"
sudo sh -c "echo 'KEYMAP=de-latin1' >> /etc/vconsole.conf"
#Install Adaptec SAS 44300, 48300, 58300 Sequencer Firmware for AIC94xx driver
git clone https://aur.archlinux.org/aic94xx-firmware.git
cd aic94xx-firmware
makepkg -sri --noconfirm
cd ..
rm -r aic94xx-firmware -f
#Install Driver for Western Digital WD7193, WD7197 and WD7296 SCSI cards
git clone https://aur.archlinux.org/wd719x-firmware.git
cd wd719x-firmware
makepkg -sri --noconfirm
cd ..
rm -r wd719x-firmware -f
#Install Driver for 
git clone  https://aur.archlinux.org/upd72020x-fw.git
cd upd72020x-fw
makepkg -sri --noconfirm
cd ..
rm -r upd72020x-fw -f
#Edit minitcpio.conf
sudo sed -i 's/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev autodetect keyboard keymap modconf block filesystems fsck)/g' /etc/mkinitcpio.conf
sudo mkinitcpio -p linux
#edit journald.conf
sudo sed -i 's/#ForwardToWall=yes/ForwardToWall=no/g' /etc/systemd/journald.conf
#Set Hostname
sudo sh -c "echo 'arch' >> /etc/hostname"
#Edit hosts
sudo sh -c "echo '127.0.0.1 localhost' >> /etc/hosts"
sudo sh -c "echo '::1 localhost' >> /etc/hosts"
sudo sh -c "echo '127.0.0.1 arch.my365way.com arch' >> /etc/hosts"
#Enforce a delay after a failed login attempt
sudo sh -c "echo 'auth optional pam_faildelay.so delay=4000000' >> /etc/pam.d/system-login"
#Enforcing strong passwords with pam_pwquality
sudo sed -i '$d' /etc/pam.d/passwd
sudo sh -c "echo 'password required pam_pwquality.so retry=2 minlen=10 difok=6 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1 [badwords=myservice mydomain] enforce_for_root' >> /etc/pam.d/passwd"
sudo sh -c "echo 'password required pam_unix.so use_authtok sha512 shadow' >> /etc/pam.d/passwd"
#Install snap
git clone https://aur.archlinux.org/snapd.git
cd snapd
makepkg -si --noconfirm
sudo systemctl enable --now snapd.socket
sudo ln -s /var/lib/snapd/snap /snap
cd ..
rm -r snapd -f
#Ensure snapd is up to date
sudo snap install core; sudo snap refresh core #do twice or reload
#Firawall with nftables
sudo pacman -S firewalld ebtables
sudo systemctl enable --now firewalld
systemctl status firewalld
sudo firewall-cmd --set-default-zone=dmz
sudo firewall-cmd --add-service https --permanent
sudo firewall-cmd --add-service http --permanent
#sudo firewall-cmd --zone=dmz --permanent --add-port=xxx/tcp
#sudo firewall-cmd --zone=dmz --permanent --remove-port=xxx/tcp
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
#Install nginx
sudo mkdir /www/html
sudo pacman -S nginx-mainline --noconfirm
sudo sed -i 's/keepalive_timeout  65;/keepalive_timeout  65; \n    types_hash_max_size 4096;/g' /etc/nginx/nginx.conf
#Set nginx Server Name, Server Status, error pages & Kextrel reverse Proxy
sudo sed -i '$d' /etc/nginx/nginx.conf
cat <<-'EOF' > /etc/nginx/nginx.conf
worker_processes  1;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    server_tokens off;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security max-age=15768000;
    sendfile on;
    keepalive_timeout 65;
    types_hash_max_size 4096;

    server {
        if ($host = arch.my365way.com) {
            return 301 https://$host$request_uri;
        }
        listen 80;
        server_name arch.my365way.com;
        return 404;
    }

    server {
        listen 443 ssl;
        server_name arch.my365way.com;

        location / {
            root /www/html;
            index index.html;
        }

        location /doublekeyencryption {
            proxy_pass         https://127.0.0.1:5001;
            proxy_http_version 1.1;
            proxy_set_header   Upgrade $http_upgrade;
            proxy_set_header   Connection keep-alive;
            proxy_set_header   Host $host;
            proxy_cache_bypass $http_upgrade;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
        }

        location /nginx_status {
            stub_status;
            allow all;
        }

        error_page 404 /404.html;
        location = /404.html {
            root /www/html/4xx_client_errors;
        }
        location = /404-style.css {
            root /www/html/4xx_client_errors;
        }

        error_page 500 502 503 504 /500.html;
        location = /500.html {
            root /www/html/5xx_client_errors;
        }
        location = /500-style.css {
            root /www/html/5xx_client_errors;
        }

        if ($request_method !~ ^(GET|HEAD|POST)$ ) {
            return 405;
        }
    
        ssl_certificate /etc/letsencrypt/live/arch.my365way.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/arch.my365way.com/privkey.pem;
        include /etc/letsencrypt/options-ssl-nginx.conf;
        ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    }    
}
EOF

#Enable nginx
sudo systemctl enable --now nginx
sudo systemctl status nginx
sudo systemctl reload nginx
sudo nginx -t
#Reboot the system
sudo reboot
#Install Certbot
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo certbot --nginx
#Set dotnet Production folder
sudo groupadd dotnet-group
sudo gpasswd -a christian dotnet-group
sudo mkdir /www/dotnet
sudo chmod 775 /www/dotnet
sudo chown -R christian:dotnet-group /www/dotnet/
cat /etc/group
ls -l /www/dotnet
#Install Microsoft.AspNetCore.App 3.1 & Microsoft.NETCore.App 3.1
wget https://download.visualstudio.microsoft.com/download/pr/d34e1a17-40d4-442d-b0e2-dc297a8742ef/e8bd62b16712bb759ed29145bde51676/dotnet-sdk-3.1.414-linux-x64.tar.gz
mkdir -p $HOME/dotnet 
tar zxf dotnet-sdk-3.1.414-linux-x64.tar.gz -C $HOME/dotnet
rm dotnet-sdk-3.1.414-linux-x64.tar.gz -f
sudo snap install dotnet-runtime-31
sudo nano ~/.bashrc
--> export DOTNET_ROOT=$HOME/dotnet
--> export PATH=$PATH:$HOME/dotnet
#Reboot the system
sudo reboot
#DotNet Info
dotnet --info
#Create RSA Key Pair
su
mkdir /www/rsa-key

openssl req -x509 -newkey rsa:2048 -keyout /www/rsa-key/encrypted-rsa-496-key.pem -out /www/rsa-key/cert.pem -days 365 -subj "/C=DE/ST=Sachsen/L=Leipzig/O=My365Way/OU=DoubleKeyEncryption/CN=arch.my365way.com/emailAddress=christian@my365way.com"
openssl rsa -in /www/rsa-key/encrypted-rsa-496-key.pem -out /www/rsa-key/private-key.pem
openssl rsa -in /www/rsa-key/encrypted-rsa-496-key.pem -pubout > /www/rsa-key/public-key.pem

sed --in-place '/-----BEGIN RSA PRIVATE KEY-----/d' /www/rsa-key/private-key.pem
sed --in-place '/-----END RSA PRIVATE KEY-----/d' /www/rsa-key/private-key.pem
tr -d '\n' < /www/rsa-key/private-key.pem > /www/rsa-key/privatekey.pem
cat /www/rsa-key/privatekey.pem

sed --in-place '/-----BEGIN PUBLIC KEY-----/d' /www/rsa-key/public-key.pem
sed --in-place '/-----END PUBLIC KEY-----/d' /www/rsa-key/public-key.pem
tr -d '\n' < /www/rsa-key/public-key.pem > /www/rsa-key/publickey.pem
cat /www/rsa-key/publickey.pem

exit
#GUID Generator
sudo mkdir /www/GUID
sudo sh -c "uuidgen --sha1 --namespace @dns --name 'arch.my365way.com' >> /www/GUID/GUID"

#Get source code repository for the Double Key Encryption (DKE)
cd /www/dotnet
git clone https://github.com/Azure-Samples/DoubleKeyEncryptionService.git

#Config appsettings.json (Client-ID: b54ee80f-b7fb-4f1e-b5a9-0d6111de0c76)
sed -i '$d' /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/appsettings.json
cat <<-'EOF' > /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/appsettings.json
{
  "AzureAd": {
    "Instance": "https://login.microsoftonline.com/",
    "ClientId": "b54ee80f-b7fb-4f1e-b5a9-0d6111de0c76", 
    "TenantId": "common",
    "Authority": "https://login.microsoftonline.com/common/v2.0",
    "TokenValidationParameters": {
      "ValidIssuers": [
        "https://sts.windows.net/630a260f-04bd-4d65-a04d-f922f6c2c4a0/"
      ]
    }
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    },
    "EventLog": {
      "LogLevel": {
        "Default": "Information"
      }
    }
  },
  "AllowedHosts": "*",
  "JwtAudience": "https://arch.my365way.com",
  "JwtAuthorization": "https://login.windows.net/common/oauth2/authorize",
  "RoleAuthorizer": {
    "LDAPPath": ""
  },
  "TestKeys": [
    {
      "Name": "doublekeyencryption",
      "Id": "GUID",
      "AuthorizedEmailAddress": ["christian@my365way.com"],
      "PublicPem" :  "publickey",
      "PrivatePem":  "privatekey"
    }
  ]
}
EOF

sed -i "s/GUID/$(cat /www/GUID/GUID)/" /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/appsettings.json
sed -i "s|privatekey|$(cat /www/rsa-key/privatekey.pem)|" /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/appsettings.json
sed -i "s|publickey|$(cat /www/rsa-key/publickey.pem)|" /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/appsettings.json

#Deaktivate Program.cs DotNet Logging
sed -i '$d' /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/Program.cs
cat <<-'EOF' > /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/Program.cs
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
namespace CustomerKeyStore
{
    using Microsoft.AspNetCore;
    using Microsoft.AspNetCore.Hosting;
    using Microsoft.Extensions.Logging;
    public static class Program
    {
        public static void Main(string[] args)
        {
            CreateWebHostBuilder(args).Build().Run();
        }

        public static IWebHostBuilder CreateWebHostBuilder(string[] args) =>
            WebHost.CreateDefaultBuilder(args)
            .UseStartup<Startup>()
            .ConfigureLogging((context, logging) =>
            {
//                logging.AddEventLog(eventLogSettings =>
//                {
//                });
            });
    }
}
EOF

#Config Startup.cs
sed -i '/#if USE_TEST_KEYS/d' /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/Startup.cs
sed -i '/#error !!!!!!!!!!!!!!!!!!!!!! Use of test keys is only supported for testing, DO NOT USE FOR PRODUCTION !!!!!!!!!!!!!!!!!!!!!!!!!!!!!/d' /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/Startup.cs
sed -i '/#endif/d' /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/Startup.cs

#Publish DotNet app
cd /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store
dotnet publish --configuration Release --nologo
dotnet run

#Create kestrel service file
su 
cat <<-'EOF' > /etc/systemd/system/customerkeystore.service
[Unit]
Description=.NET customerkeystore App running on Arch

[Service]
WorkingDirectory=/www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/bin/Release/netcoreapp3.1/publish/
ExecStart=/home/christian/dotnet/dotnet /www/dotnet/DoubleKeyEncryptionService/src/customer-key-store/bin/Release/netcoreapp3.1/customerkeystore.dll
Restart=always
RestartSec=10
KillSignal=SIGINT
SyslogIdentifier=My365Way-customerkeystore 
User=christian
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false

[Install]
WantedBy=multi-user.target
EOF

#Start and enable kesterl service
sudo systemctl enable customerkeystore.service
sudo systemctl start customerkeystore.service
sudo systemctl status customerkeystore.service
sudo systemctl stop customerkeystore.service
sudo journalctl -fu customerkeystore.service
sudo systemctl daemon-reload
