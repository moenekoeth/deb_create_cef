packer {
  required_plugins {
    docker = {
      version = ">= 1.0.8"
      source  = "github.com/hashicorp/docker"
    }
  }
}
variable "ci_tag_release" {
  type =  string
  default = env("THIS_CI_COMMIT_TAG") == "" ? "latest" : env("THIS_CI_COMMIT_TAG")
  description = "CI Commit tag for tagging images"
}

variable "chormium_cached_storage" {
  type =  string
  default = env("CACHED_CHROME_SRC_DIR")
  description = "Host directory for cahced chromium source storage"
}

variable "docker_reg_login_name" {
  type =  string
  default = env("DOCKER_REG_LOGIN_NAME")
  sensitive = true
  description = "Docker Registry Username"
}

variable "docker_reg_login_password" {
  type =  string
  default = env("DOCKER_REG_LOGIN_PASSWORD")
  sensitive = true
  description = "Docker Registry Password"
}

variable "docker_reg_login_base" {
  type =  string
  default = env("DOCKER_REG_LOGIN_BASE") == "" ? "deb-create-cef" : env("DOCKER_REG_LOGIN_BASE")
  sensitive = true
  description = "Docker Registry Server"
}

variable "docker_reg_login_server" {
  type =  string
  default = env("DOCKER_REG_LOGIN_SERVER")
  sensitive = true
  description = "Docker Registry Server"
}

variable "docker_reg_login_pull" {
  default = env("DOCKER_REG_LOGIN_PULL")
  description = "Docker Registry Server Pulling"
}

variable "cef_deb_image_use_compression" {
  type =  string
  default = env("CEF_DEB_IMAGE_USE_COMPRESSION") == "" ? "true" : env("CEF_DEB_IMAGE_USE_COMPRESSION")
  description = "Use compression to make the source image smaller."
}

variable "cef_compress_src" {
    default = <<EOF
      mkdir /codezip
      cd /
      # Zip up source code
      echo '>>>>>>>> Compressing source code'
      tar --use-compress-program=pigz -cf codezip/codezipped.tar.gz code
      # remove code directory
      echo '>>>>>>>> Removing original source'
      rm -rf /code
EOF

}

locals {
  cef_compress_do = var.cef_deb_image_use_compression == "true" ? var.cef_compress_src : "echo 'skipping compression'"
}


source "docker" "debianbuilder" {
  login = var.docker_reg_login_pull == "" ? true : var.docker_reg_login_pull
  login_username = var.docker_reg_login_name
  login_password = var.docker_reg_login_password
  login_server = var.docker_reg_login_server
  pull = var.docker_reg_login_pull == "" ? true : var.docker_reg_login_pull
  image  = join("",[var.docker_reg_login_base,"/deb-cef-builder:",var.ci_tag_release])
  commit = true
volumes = {
    join("",[var.chormium_cached_storage,"/chrome_src/"])="/chrome_src/",
    join("",[var.chormium_cached_storage,"/output/"])="/output/"
} 
  changes = [
    "WORKDIR /code",
    "VOLUME /chrome_src/",
    "ENV PATH=/code/depot_tools:$PATH"
  ]
}




variable "cef_setup_tools" {
    default = <<EOF

# set up compression tools
apt-get install -y pigz
python3 -m pip install rapidgzip
cd /code

# disable git warnings
git config --global advice.detachedHead "false"

# clone depot_tools
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git

# get cef tool automate-git.py from bitbucket
cd /code/automate
wget https://bitbucket.org/chromiumembedded/cef/raw/master/tools/automate/automate-git.py

# see if we have our chromium source cached, use cache if we have it
if find /chrome_src/ -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    echo '>>>>>>>> chromium source cached, using cache';
    cd /code/chromium_git/;
    cp -r /chrome_src/chromium chromium ; 
    echo 'copy complete'
else echo '>>>>>>>> No chromium source cached, it will be downloaded'; 
    export GN_DEFINES="is_official_build=true use_sysroot=true use_allocator=none symbol_level=1 is_cfi=false use_jumbo_build=true proprietary_codecs=true ffmpeg_branding=Chrome"

cd /code/

# Get the matching version of Chromium from the bitbucket cef1
wget https://bitbucket.org/chromiumembedded/cef/raw/master/CHROMIUM_BUILD_COMPATIBILITY.txt

echo '>>>>>>>> Downloading chromium base fetch'
    #mkdir -p /code/chromium_git/chromium/
    #cd /code/chromium_git/chromium/
    CHROMIUM_BUILD_COMPATIBILITY=`cat /code/CHROMIUM_BUILD_COMPATIBILITY.txt | tail -n3 | sed "s/'/"'"'"/g"  | jq -r .chromium_checkout`
    CHROMIUM_BUILD_COMPATIBILITY_TAG=`echo "$CHROMIUM_BUILD_COMPATIBILITY" | sed 's|refs/tags/||'`

echo '>>>>>>>> Setup automate script'
    echo '#!/bin/bash'"
    set GN_DEFINES='$GN_DEFINES'
    "'python3 -u ../automate/automate-git-eff.py --download-dir=/code/chromium_git \
    --depot-tools-dir=/code/depot_tools --no-distrib --no-build' > /code/chromium_git/update.sh
    cd /code/automate/
    # Make automate-git.py a little more efficient.
    cat /code/automate/automate-git.py | sed 's|fetch\"|fetch --depth 4 origin +'"'$CHROMIUM_BUILD_COMPATIBILITY"':chromium_'"$CHROMIUM_BUILD_COMPATIBILITY_TAG'"'"|' > /code/automate/automate-git-eff.py
    sed -i 's/fetch --tags/tag/' /code/automate/automate-git-eff.py
    sed -i 's/--nohooks --with_branch_heads/--nohooks --no-history --shallow --with_branch_heads/' /code/automate/automate-git-eff.py
echo '>>>>>>>> Starting automate script - no build'
    chmod 755 /code/chromium_git/update.sh
    cd /code/chromium_git/
    ./update.sh

echo '>>>>>>>> Automate script complete'

fi

EOF
}


build {
  name = "cef-build-base"
  sources = ["source.docker.debianbuilder"]


  provisioner "shell" {
    skip_clean = true
    inline = [
      # Create directory structure, and cleanup from builder
      "mkdir -p /code",
      "mkdir -p /code/automate",
      "rm -rf /code/chromium_git || echo ''",
      "rm -rf /code/cef || echo ''",
      "mkdir -p /code/chromium_git",
      "mkdir -p /code/linux",
      "cd /code",
      # Run our source code download and set up
      "echo '>>>>>>>> Starting source collection'",
      var.cef_setup_tools,
      local.cef_compress_do

    ]
  }

  post-processors {
    post-processor "docker-tag" {
      repository = join("",[var.docker_reg_login_base,"/deb-cef-build-base"])
      tags       = [var.ci_tag_release]
    }
    post-processor "docker-push" {
      login = var.docker_reg_login_pull == "" ? true : var.docker_reg_login_pull
      login_username = var.docker_reg_login_name
      login_password = var.docker_reg_login_password
      login_server = var.docker_reg_login_server
    }
  } 
}