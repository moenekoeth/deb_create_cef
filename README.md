# Project to build chromium using packer   

## Must set environment variables in gitlab variables:   

Docker repository Username for storing builds 
```
DOCKER_REG_LOGIN_NAME
```


Docker repository Password for storing builds   
```
DOCKER_REG_LOGIN_PASSWORD
```
  

Docker repository Server for storing builds    
Example:   
https://somedockerregdomian.com:5000  
```
DOCKER_REG_LOGIN_SERVER
```


Group for build, will be the domain if custom registry   
Will be the username if using docker.io 
```
DOCKER_REG_LOGIN_BASE
```



# Local run

To run locally, set the DOCKER_REG_* vars then run:

```
chmod +x ./setup.sh ;   
./setup.sh
```