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
  default = env("THIS_CI_COMMIT_TAG")  == "" ? "latest" : env("THIS_CI_COMMIT_TAG")
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


source "docker" "debian" {
  image  = "debian:bullseye"
  commit = true
  volumes = {
    join("",[var.chormium_cached_storage,"/chrome_src/"])="/chrome_src/"
  } 
  changes = [
    "WORKDIR /code",
    "VOLUME /chrome_src/",
    "ENV PATH=/code/depot_tools:$PATH"
  ]
}




variable "cef_install_build_deps" {
    default = <<EOF
cd /code

# Update debian repo
apt-get update

# install sudo and debconf-utils
apt-get install -y sudo debconf-utils

# Set debconf to not ask for selections
echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections

# set up preregs for chromium build tools
apt-get install -y jq curl wget file lsb-release procps python3 python3-pip

# get install-build-deps from chromium repo
curl 'https://chromium.googlesource.com/chromium/src/+/main/build/install-build-deps.py?format=TEXT' | base64 -d > install-build-deps.py

# install build tool dependencies
python3 ./install-build-deps.py --no-arm --no-chromeos-fonts --no-nacl --no-prompt

# install dataclasses importlib_metadata
python3 -m pip install dataclasses importlib_metadata

# install gtk dev libs
apt-get install -y libgtk2.0-dev libgtk-3-dev

# clean up apt-get
apt-get purge -y --auto-remove
EOF
}



build {
  name = "cef-build-setup"
  sources = ["source.docker.debian"]


  provisioner "shell" {
    inline = [
      # Create directory structure
      "mkdir -p /code",
      "mkdir -p /code/automate",
      "mkdir -p /code/chromium_git",
      "mkdir -p /code/linux",
      join(" ",["echo 'setting up for docker user",var.docker_reg_login_name,"'"]),
      "cd /code",
      var.cef_install_build_deps

    ]
  }
  post-processors {
    post-processor "docker-tag" {
      repository = join("",[var.docker_reg_login_base,"/deb-cef-builder"])
      force      = true
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