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


variable "cef_deb_remove_src_in_final" {
  type =  string
  default = env("CEF_DEB_REMOVE_SRC_IN_FINAL") == "" ? "false" : env("CEF_DEB_REMOVE_SRC_IN_FINAL")
  description = "Remove the source code in the final image"
}

variable "cef_deb_image_use_compression" {
  type =  string
  default = env("CEF_DEB_IMAGE_USE_COMPRESSION") == "" ? "true" : env("CEF_DEB_IMAGE_USE_COMPRESSION")
  description = "Use compression to make the source image smaller."
}

variable "cef_gpu_job_count" {
  type =  string
  default = env("CEF_GPU_JOB_COUNT") == "" ? "0" : env("CEF_GPU_JOB_COUNT")
  description = "Number of jobs to compile with if using gpu"
}

variable "cef_gpu_job_ready" {
    default = <<EOF
export USE_GPU=`/code/gpu_check.sh | tail -n1 | tr -d '\n' | tr -d ' '`
echo "use gpu result: $USE_GPU"


EOF
}



variable "cef_uncompress_src" {
    default = <<EOF
      # Remove any left over /code
      rm -rf /code || echo ''
      # Unpack source code
      cd /codezip
      echo '>>>>>>>> Uncompressing source code'
      tar --use-compress-program=rapidgzip -xf codezipped.tar.gz -C ..
      echo '>>>>>>>> Removing compressed src archive.'
      rm -rf /codezip
EOF

}

locals {
  cef_uncompress_do = var.cef_deb_image_use_compression == "true" ? var.cef_uncompress_src : "echo 'skipping compression'"
  cef_cef_gpu_do = var.cef_gpu_job_count == "0" ? "echo 'skipping gpu check'" : join("",[var.cef_gpu_job_ready,"sed -i 's|-C |-j",var.cef_gpu_job_count," -C |' /code/automate/automate-git-eff.py"])
  remove_src_in_final_do = var.cef_deb_remove_src_in_final == "true" ? "rm -rf /code" : "echo 'skipping src removal'"

}



source "docker" "debianready" {
  login = var.docker_reg_login_pull == "" ? true : var.docker_reg_login_pull
  login_username = var.docker_reg_login_name
  login_password = var.docker_reg_login_password
  login_server = var.docker_reg_login_server
  pull = var.docker_reg_login_pull == "" ? true : var.docker_reg_login_pull
  image  = join("",[var.docker_reg_login_base,"/deb-cef-build-base:",var.ci_tag_release])
  run_command = ["--gpus=all","-d", "-i", "-t", "--entrypoint=/bin/sh", "--", "{{.Image}}"]
  commit = true
  volumes = {
    join("",[var.chormium_cached_storage,"/output/"])="/output/"
  } 
  changes = [
    "WORKDIR /code",
    "VOLUME /output/",
    "ENV PATH=/code/depot_tools:$PATH"
  ]
}



variable "set_up_gpu_check" {
  default = <<EOF
echo '#!/bin/bash

# Function to install packages if they are missing
install_package() {
    sudo apt-get install -y "$1"
}

# Check for required packages
install_package "pciutils"
install_package "mesa-utils"

# Get GPU information
GPU_INFO=$(lspci | grep -i vga)
echo "Detected GPU: $GPU_INFO"

if echo "$GPU_INFO" | grep -i "nvidia" >/dev/null; then
    echo "NVIDIA GPU detected"
    
    # Check if nvidia-utils is installed
    if ! command -v nvidia-smi >/dev/null; then
        install_package "nvidia-utils"
    fi
    echo "true"
    
    
elif echo "$GPU_INFO" | grep -i "amd" >/dev/null || echo "$GPU_INFO" | grep -i "radeon" >/dev/null; then
    echo "AMD GPU detected"
    
    # Check if radeontop is installed
    if ! command -v radeontop >/dev/null; then
        install_package "radeontop"
    fi
    
    radeontop -d-
    echo "true"
    
elif echo "$GPU_INFO" | grep -i "intel" >/dev/null; then
    echo "Intel GPU detected"
    
    # Check if intel-gpu-tools is installed
    if ! command -v intel_gpu_top >/dev/null; then
        install_package "intel-gpu-tools"
    fi
    echo "true"
    
else
    echo "false"
fi

' > /code/gpu_check.sh
chmod +x /code/gpu_check.sh

EOF
}


variable "cef_compile_build_1" {
    default = <<EOF

cd /code/chromium_git/chromium/

# Overwite our .glcient
echo 'solutions = [
  {
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "custom_deps": {
         "src/third_party/WebKit/LayoutTests": None,
      "src/chrome_frame/tools/test/reference_build/chrome": None,
      "src/chrome/tools/test/reference_build/chrome_mac": None,
      "src/chrome/tools/test/reference_build/chrome_win": None,
      "src/chrome/tools/test/reference_build/chrome_linux": None
    },
    "custom_vars": {"checkout_pgo_profiles": True
    },
  },
]
' > .gclient

cd /code/chromium_git/chromium/src

# checkout our current src version of chromium
git checkout FETCH_HEAD

# Final gclient sync, clean up not used directories
echo '>>>>>>>> Running gclient sync'
gclient sync -D \
    -j16 \
    --nohooks \
    --no-history \
    --shallow 
  
# Final glcient runhooks
echo '>>>>>>>> Running gclient runhooks'
   cd /code/chromium_git/chromium/src/
   gclient runhooks

cd /code/chromium_git/chromium/src/cef

# Update build configuration
EXTRA_REQS="set(USE_SANDBOX OFF)
set(USE_PROPRIETARY_CODECS ON)
set(CHROME_BRANDING ON)" 

echo "$EXTRA_REQS" >> /code/chromium_git/chromium/src/cef/cmake/cef_variables.cmake
echo "$EXTRA_REQS" >> /code/chromium_git/cef/cmake/cef_variables.cmake



export CEF_USE_GN=1
#export CEF_ARCHIVE_FORMAT=tar.bz2
export USE_GPU=false

EOF
}

variable "cef_compile_build_2" {
    default = <<EOF



export GN_DEFINES="ffmpeg_branding=Chrome use_gpu=$USE_GPU use_gtk3=true is_official_build=true proprietary_codecs=true use_sysroot=true symbol_level=1 enable_vr=false"

echo '>>>>>>>> Setup automate script'
    echo '#!/bin/bash'"
    set CEF_USE_GN='$CEF_USE_GN'
    set GN_DEFINES='$GN_DEFINES'
    "'python3 -u ../automate/automate-git-eff.py  --download-dir=/code/chromium_git --depot-tools-dir=/code/depot_tools \
 --branch=master --force-config --minimal-distrib-only --verbose-build \
 --build-target="cefsimple" --x64-build --no-debug-build --force-build --no-release-tests'  > /code/chromium_git/build.sh
chmod 755 /code/chromium_git/build.sh
# Cleanup any remaining build files before make our final version
rm -r /code/chromium_git/chromium/src/out
cd /code/chromium_git/

# run our build
./build.sh
cd /code/chromium_git/chromium/src
export CHROME_DEVEL_SANDBOX=/usr/local/sbin/chrome-devel-sandbox
BUILDTYPE=Release_GN_x64 ./build/update-linux-sandbox.sh

EOF
}



build {
  name = "cef-build-comp"
  sources = ["source.docker.debianready"]


  provisioner "shell" {
    skip_clean = true
    inline = [
      local.cef_uncompress_do,
      # Set up gpu compiler
      "echo '>>>>>>>> Setting up GPU compiling tools'",
      var.set_up_gpu_check,
      # Run our comiling 
      "echo '>>>>>>>> Starting compile process'",
      var.cef_compile_build_1,
      local.cef_cef_gpu_do,
      var.cef_compile_build_2,
      # copy our binary distribution to /output
      "mkdir -p /output/Release_GN_x64",
      "mkdir -p /output/binary_distrib",
      "cp -r /code/chromium_git/chromium/src/cef/binary_distrib /output/binary_distrib",
      "cp -r /code/chromium_git/chromium/src/out/Release_GN_x64 /output/Release_GN_x64",
      "cd /output",
      #"mv ./cef_binary_*.tar.bz2 ./cef-minimal-x64.tar.bz2",
      local.remove_src_in_final_do

    ]
  }

  post-processors {
    post-processor "docker-tag" {
      repository = join("",[var.docker_reg_login_base,"/deb-cef-compiler"])
      force      = true
      tags       = [var.ci_tag_release]
    }
    post-processor "docker-push" {
      login = var.docker_reg_login_pull == "" ? false : var.docker_reg_login_pull
      login_username = var.docker_reg_login_name
      login_password = var.docker_reg_login_password
      login_server = var.docker_reg_login_server
    }
  } 
}
