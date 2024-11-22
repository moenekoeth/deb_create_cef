
if [ "$DOCKER_REG_LOGIN_PULL" = "" ]
then
   export DOCKER_REG_LOGIN_PULL="true"
fi 

if [ "$CEF_DEB_IMAGE_USE_COMPRESSION" = "" ]
then
   export CEF_DEB_IMAGE_USE_COMPRESSION="true"
fi 

if [ "$CEF_DEB_REMOVE_SRC_IN_FINAL" = "" ]
then
   export CEF_DEB_REMOVE_SRC_IN_FINAL="false"
fi 

if [ "$CEF_GPU_JOB_COUNT" = "" ]
then
   export CEF_GPU_JOB_COUNT="0"
fi 




echo "Shared volume directory set to $CACHED_CHROME_SRC_DIR"
sleep 2
mkdir -p $CACHED_CHROME_SRC_DIR/chrome_src/ 2>/dev/null
mkdir -p $CACHED_CHROME_SRC_DIR/output/ 2>/dev/null
docker stop debchc 2>/dev/null
docker rmi debchi 2>/dev/null
docker build . -t debchi
docker run --gpus=all -e CEF_GPU_JOB_COUNT="$CEF_GPU_JOB_COUNT" -e CEF_DEB_REMOVE_SRC_IN_FINAL="$CEF_DEB_REMOVE_SRC_IN_FINAL" -e CEF_DEB_IMAGE_USE_COMPRESSION="$CEF_DEB_IMAGE_USE_COMPRESSION" -e CACHED_CHROME_SRC_DIR="$CACHED_CHROME_SRC_DIR" -e THIS_CI_COMMIT_TAG="latest" -e DOCKER_REG_LOGIN_PULL="$DOCKER_REG_LOGIN_PULL" -e DOCKER_REG_LOGIN_NAME="$DOCKER_REG_LOGIN_NAME" -e DOCKER_REG_LOGIN_PASSWORD="$DOCKER_REG_LOGIN_PASSWORD" \
-e DOCKER_REG_LOGIN_SERVER="$DOCKER_REG_LOGIN_SERVER" -e DOCKER_REG_LOGIN_BASE="$DOCKER_REG_LOGIN_BASE" -v '/var/run/docker.sock:/var/run/docker.sock' \
 --rm=true --name debchc debchi