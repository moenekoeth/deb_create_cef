debcefbuilderimg=`docker images | grep -o deb-cef-builder | head -n1`

if [[ "$debcefbuilderimg" == "deb-cef-builder" ]]
then
   echo "$debcefbuilderimg exists"
else
   packer init builder.pkr.hcl
   packer validate builder.pkr.hcl
   packer build builder.pkr.hcl
fi

debcefbuildbaseimg=`docker images | grep -o deb-cef-build-base | head -n1`

if [[ "$debcefbuildbaseimg" == "deb-cef-build-base" ]]
then
   echo "$debcefbuildbaseimg exists"
else
    packer init packer.pkr.hcl
    packer validate packer.pkr.hcl
    packer build packer.pkr.hcl
fi

debcefbuildcompimg=`docker images | grep -o deb-cef-compiler | head -n1`

if [[ "$debcefbuildcompimg" == "deb-cef-compiler" ]]
then
   echo "$debcefbuildcompimg exists"
else
    packer init compiler.pkr.hcl
    packer validate compiler.pkr.hcl
    packer build compiler.pkr.hcl
fi