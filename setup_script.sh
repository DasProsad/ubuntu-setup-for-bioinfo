#!/usr/bin/env bash
#
# ============================================================
#
#  Ubuntu Setup Script ( Tested on Ubuntu 20.4, 22.04)
#  Version: 0.2
#  Author: prosad das ( https://github.com/dasprosad )
#  License: GPL 2.0
#
# ============================================================
#
#  A shell script to help with the quick set up and installation
#  of tools and applications for bioinformatics
#
#  Quick Instructions:
# 
#  1. Make the script executable:
#     chmod +x ./setup_script.sh
#
#  2. Run the script:
#     sudo ./setup_script.sh
#
#  3. It will require root password.
#
# ============================================================ 

set -euo pipefail

# ------------------------------------------------------------
#
# COLOR LOGGING
#
# ------------------------------------------------------------

BOLD="\033[1;1m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
WHITE="\033[37m"
RESET="\033[10m;"

log() {
	local level="$1"; shift
	local color="$RESET"

	case "$level" in
		INFO)   color="$GREEN" ;;
		WARN)   color="$YELLOW" ;;
		ERROR)  color="$RED" ;;
		STEP)   color="$BLUE" ;;
	esac

	printf "%b[%s] [%s] %s%b\n" \
		"$color" \
		"$(date '+%Y-%m-%d %H:%M:%S')" \
		"$level" \
		"$*" \
		"$RESET"
}

# -------------------------------------------------------------
#
# VALIDATE ROOT ACCESS
#
# -------------------------------------------------------------


require_root() {
	[[ $EUID -ne 0 ]] && {
		log ERROR "This script must be run as root (sudo)"
		exit 1
	}
}

# -------------------------------------------------------------
#
# UTILITY HELPERS
#
# -------------------------------------------------------------

rettry() {
	local attempts="$1"; shift
	local delay="$1"; shift

	for i in $(seq 1 "$attempts"); do
		"$@" && return 0;
		log WARN "Attempt $i/$attempts failed: $*"
		sleep "$delay"
	done

	log ERROR "Command failed after $attempts attempts: $*"
	return 1
}

ensure_dir() { mkdir -p "$1"; }

ensure_clean_dir() { rm -rf "$1" && mkdir -p "$1"; }

is_bash() {
	if [[ -z "${BASH_VERSION} " ]]; then
		echo -e "${BOLD}${RED}ERROR: ${WHITE}Please run this script using ${GREEN}bash${WHITE}, not ${YELLOW}sh or other shells${WHITE}.${RESET}" >&2
		exit 21
	fi
}

# ------------------------------------------------------------
#
# SYSTEM CONFIGURATION
#
# ------------------------------------------------------------

set_apt_mirrors() {
	log STEP "Configuring US APT mirrors"

	cp /etc/apt/sources.list /etc/apt/soiurces.list.bkp

	sed -i /etc/apt/sources.list 's|deb http://archive.ubuntu.com/ubuntu|deb https://us.archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list

}

system_update() {
	log STEP "Updating system packages"
	
	retry 3 2 apt update
	retry 3 2 apt -y upgrade
}

install_basic_packages() {
	log STEP "Installing base packages"

	retry 3 2 apt install -y \
		ca-certificates \
		autoconf \
		automake \
		libtool \
		zlib1g-dev \
		libbz2-dev \
		liblzma-dev \
		net-tools \
		wget \
		curl \
		git \
		gnupg \
		build-essential \
		parallel \
		tmux \
		openssh-server \
		vim \
		texlive-full
}

# -----------------------------------------------------------
#
# INSTALL DOCKER
#
# -----------------------------------------------------------

install_docker() {
	log STEP "Installing docker"

	install -m 0755 -d /etc/apt/keyrings
	
	retry 3 2 curl -fsSL \
	https://download.docker.com/linux/ubuntu/gpg \
	-o /etc/apt/keyrings/docker.asc

	chmod a+r /etc/apt/keyrings/docker.asc

	local codename=$( . /etc/os-release && "${UBUNTU_CODENAME:-$VERSION_CODENAME}" )

	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
		https://download.docker.com/linux/ubuntu $codename stable" \
		| tee /etc/apt/sources.list.d/docker.list > /dev/null

	retry 3 2 apt update
	retry 3 2 apt install -y \
		docker-ce \
		docker-ce-cli \
		containerd.io \
		docker-buildx-plugin \
		docker-compose-plugin

	systemctl enable --now docker

}

pull_docker_images(){
	log STEP "Pulling docker images"

	docker pull pinetree1/crispr-dav:latest
	docker pull bioconductor/bioconductor_docker:devel
	docker pull zymoresearch/bcl2fastq:latest
}

# ------------------------------------------------------------
#
# INSTALL AND CONFIGURE MINICONDA
#
# ------------------------------------------------------------

install_miniconda() {
	log STEP "Installing Miniconda"
	
	ensure_dir ~/miniconda3
	retry 3 2 wget \
	https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
	-O ~/miniconda3/miniconda.sh

	bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
	rm ~/miniconda3/bin/conda init bash
}

configure_conda() {
	log INFO "Configuring conda channels"

	conda config --add channels defaults
	conda config --add channels bioconda
	conda config --add channels conda-forge
}

install_conda_env() {
	log STEP "Installing conda environments"

	conda create -y -n crispresso2_env crispresso2
	conda create -y -n cutadapt_env cutadapt
	conda create -y -n python2_env python==2.7.18
	conda create -y -n python3.9_env python=3.9
}

# -----------------------------------------------------------
#
# BUILD AND INSTALL PACKAGES FROM SOURCE
#
# -----------------------------------------------------------

build_dir="/tmp/build"

install_from_git() {
	local url="$1"
	local name="$2"
	local build_cmd="$3"

	log STEP "Installing $name from source"

	cd "$build_dir"
	retry 3 2 git clone --depth 1 "$url" "$name"
	cd "$name"

	eval "$build_cmd"
}

install_bio_tools() {
	log STEP "Installing genomic tools from soucre"

	install_from_git \
		'https://github.com/samtools/samtools.git' \
		'samtools' \
		"./configure --prefix=/usr/local && make && make install"
	
	install_from_git \
		'https://github.com/lh3/bwa.git' \
		'bwa' \
		"make && cp bwa /usr/local/bin" 
	
	install_from_git \
		'https://github.com/pezmaster31/bamtools.git' \
		'bamtools' \
		"mkdir -p build && cd build && cmake -DCMAKE_INSTALL_PREFIX=/usr/local .. && make && make install"

	install_from_git \
		'https://github.com/BenLangmead/bowtie2.git' \
		'bowtie2' \
		"make && cp bowtie2* /usr/local/bin"

	install_from_git \
		'https://github.com/vcftools/vcftools.git' \
		'vcftools' \
		"autogen.sh && ./configure --prefix=/usr/local && make && make install"

	install_from_git \
		'https://github.com/samtools/bcftools.git' \
		'bcftools' \
		"./configure --prefix=/usr/local && make && make install"
}

# --------------------------------------------------------------------------
#
# CONFIGURE VIM AND BASH
#
# --------------------------------------------------------------------------

configure_vimrc() {
	log SETUP "Setting up vimrc"

	# Install vim-plug
	retry 3 2 curl -fLo ~/.vim/autolaod/plug.vim --create-dirs \
		https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

	local vimrc="$HOME/.vimrc"
	
	cat > "$vimrc" << 'EOF'
" Basic config
set number
set relativenumber
set tabstop=4
set shiftwidth=4
set noexpandtab
set autoindent
set smartindent
set laststatus=2
set nowrap
syntax on
set mouse=a
	
" Autoload vim-plug
call plug#begin('~/.vim/plugged')

" Status-bar
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
	
" Julia syntax highlighting
Plug 'JuliaEditorSupport/julia-vim'
	
" Nim syntax highlighting
Plug 'zah/nim.vim'

call plug#end()

EOF

		echo ".vimrc created at $vimrc"
}

configure_bashrc() {
	log SETUP "Setting up bashrc"

	echo 'PS1=$( 
	EXIT_CODE=$?; 
	if [ $EXIT_CODE -ne 0 ]; then 
    	EC="\[\e[91;1m\]$EXIT_CODE\[\e[0m\]"; 
	else 
    	EC="\[\e[32m\]0\[\e[0m\]"; 
	fi; 
	echo -n "[\[\e[38;5;154m\]\u\[\e[0m\]@\[\e[38;5;200m\]\H\[\e[0m\] \[\e[38;5;45m\]\w\[\e[0m\]]-[${EC}]\[\e[38;5;154m\]\\$\[\e[0m\] "
	)' >> ~/.bashrc

	source ~/.bashrc
}

# --------------------------------------------------------------------------
#
# MAIN WORKFLOW
#
# --------------------------------------------------------------------------

main() {
		
	# 0.1. Check the script was run as root
	require_root

	# 0.2 Check bash is the shell
	is_bash

	log INFO "Starting Ubuntu setup script"
	ensure_clean_dir "$build_dir"

	# 1. Update to US mirrors and get update
	set_apt_mirrors
	system_update

	# 2. Install basic required packages
	install_basic_packages
	
	# 3. Configure vim and bash
	configure_bashrc
	configure_vimrc

	# 4. Install docker and pull required images
	install_docker
	pull_docker_images

	# 5. Setup and install miniconda
	install_miniconda
	configure_conda
	install_conda_envs

	# 6. Install genomic tools from source
	install_bio_tools

	log INFO "CLeaning up build directory"
	rm -rf "$build_dir"

	log INFO "Setup completed succuessfully!"
}

main "$@"
