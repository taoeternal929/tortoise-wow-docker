-- Allow mangos user to connect from any Docker network host
GRANT ALL PRIVILEGES ON *.* TO 'mangos'@'%' IDENTIFIED BY 'mangos';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'yourRootPassword';
FLUSH PRIVILEGES;
