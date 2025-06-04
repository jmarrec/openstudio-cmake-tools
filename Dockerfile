# This is a image used to build openstudio for ubuntu platforms.
# All of the developer tools are included and the only thing that needs to be done is cloning the repo
# and running cmake setup.

# [Choice] focal (20.04), jammy (22.04), noble (24.04)
ARG VARIANT="focal"
FROM ubuntu:${VARIANT}

# Restate the variant to use it later
ARG VARIANT

#RUN useradd -rm -d /home/ubuntu -s /bin/bash -g root -G sudo -u 1001 ubuntu
USER root
ENV HOME="/home/root"
WORKDIR ${HOME}

ENV TZ=US
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update -qq --fix-missing && apt-get install -y --no-install-recommends --no-install-suggests \
    curl vim lsb-release build-essential git libssl-dev libxt-dev \
    libncurses5-dev libgl1-mesa-dev autoconf libexpat1-dev libpng-dev libfreetype6-dev \
    libdbus-glib-1-dev libglib2.0-dev libfontconfig1-dev libxi-dev libxrender-dev \
    libicu-dev chrpath bison libffi-dev libgdbm-dev libqdbm-dev \
    libreadline-dev libyaml-dev libharfbuzz-dev libgmp-dev patchelf python3 python3-pip python3-dev \
    lcov wget ninja-build gpg-agent software-properties-common ca-certificates pkgconf \
    jq zip unzip p7zip-full p7zip-rar aria2 file openssh-client tree bash-completion ripgrep \
    groff less \
    && ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        CLI_ZIP="awscli-exe-linux-x86_64.zip"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        CLI_ZIP="awscli-exe-linux-aarch64.zip"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi \
    && curl "https://awscli.amazonaws.com/${CLI_ZIP}" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Set the locale
RUN apt-get -y --no-install-recommends --no-install-suggests install locales \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    GTEST_COLOR=1 \
    CMAKE_EXPORT_COMPILE_COMMANDS=ON \
    NINJA_STATUS="[%p][%f/%t] "

# Optionally: use a specific GCC version
# This Dockerfile should support gcc-[7, 8, 9, 10, 11, 13], cf the ppa
ARG GCC_VER
# Add gcc-${GCC_VER}
# RUN "echo GCC_VER=${GCC_VER}" >> /etc/environment
RUN if [ -n "${GCC_VER}" ]; then \
      add-apt-repository -y ppa:ubuntu-toolchain-r/test \
      && apt-get update -qq && export DEBIAN_FRONTEND=noninteractive \
      && apt-get install -y --no-install-recommends gcc-${GCC_VER} g++-${GCC_VER} gdb \
      && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${GCC_VER} 100 \
                             --slave /usr/bin/g++ g++ /usr/bin/g++-${GCC_VER} \
                             --slave /usr/bin/gcov gcov /usr/bin/gcov-${GCC_VER} \
    ; fi

# Setup the GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt update && apt install gh -y

 # Install cmake from PPA
RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null \
        | gpg --dearmor - | tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null \
    && apt-add-repository -y "deb https://apt.kitware.com/ubuntu/ $(lsb_release -cs) main" \
    && apt-get update -qq && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends cmake cmake-curses-gui

# Install python from pyenv
ARG PYTHON_VERSION=3.12.2
# NOTE: We're placing pyenv and rbenv at /opt/ instead of $HOME/.pyenv, because the entire HOME directory is bind-mounted on CI, so it would be obscured by the mount
ENV PYENV_ROOT=/opt/pyenv \
    PATH=/opt/pyenv/shims:/opt/pyenv/bin:${PATH} \
    Python_ROOT_DIR=/opt/pyenv/versions/${PYTHON_VERSION} \
    PYTHON_VERSION=${PYTHON_VERSION}

# Install python from pyenv
RUN apt-get install -y build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev curl \
        libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    && curl https://pyenv.run | bash \
    && PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install ${PYTHON_VERSION} \
    && pyenv global ${PYTHON_VERSION} \
    && pip install -q --upgrade --no-cache-dir pip setuptools

# Install conan (and configure) and some packages
RUN python --version \
    && pip install "conan==2.17.0" gcovr numpy pytest pytest-xdist twine requests packaging \
    && conan --version \
    && conan profile detect \
    && sed -i 's/cppstd=.*$/cppstd=20/g' $HOME/.conan2/profiles/default \
    && echo "core:non_interactive = True" >> $HOME/.conan2/global.conf \
    && echo "core.download:parallel = {{os.cpu_count() - 2}}" >> $HOME/.conan2/global.conf \
    && echo "core.sources:download_cache = $HOME/.conan2/.conan-download-cache" >> $HOME/.conan2/global.conf \
    && conan remote add --force nrel-v2 https://conan.openstudio.net/artifactory/api/conan/conan-v2 \
    && echo "Displaying default profile" && cat $HOME/.conan2/profiles/default \
    && echo "Displaying global.conf" && cat $HOME/.conan2/global.conf

# Install Ruby from RVM
ARG RUBY_VERSION=3.2.2
ARG OPENSSL_VERSION=3.1.0
ARG BUNDLER_VERSION=2.4.10
RUN cd /tmp && echo "Start by installing ${OPENSSL_VERSION}" \
    && wget https://www.openssl.org/source/old/$(echo ${OPENSSL_VERSION} | cut -d '.' -f 1,2)/openssl-${OPENSSL_VERSION}.tar.gz \
    && tar xfz openssl-${OPENSSL_VERSION}.tar.gz && cd openssl-${OPENSSL_VERSION} \
    && ./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl '-Wl,-rpath,$(LIBRPATH)' \
    && make --quiet -j $(nproc) && make install --quiet

ENV RBENV_ROOT=/opt/rbenv \
    PATH=/opt/rbenv/shims:/opt/rbenv/bin:${PATH}

# Install ruby via rbenv
# https://github.com/rbenv/ruby-build/wiki#ubuntudebianmint
# focal is giving me trouble, tried PKG_CONFIG_PATH=/usr/local/ssl/lib64/pkgconfig, passing --with-openssl-dir
# and even RUBY_BUILD_VENDOR_OPENSSL=1. I don't think we care about the openssl version used anymore (our conan ruby is used for building)
RUN apt-get install -y autoconf patch build-essential rustc libssl-dev libyaml-dev libreadline6-dev zlib1g-dev \
        libgmp-dev libncurses5-dev libffi-dev libgdbm6 libgdbm-dev libdb-dev uuid-dev \
    && curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash \
    && RUBY_CONFIGURE_OPTS="--disable-shared" rbenv install -v ${RUBY_VERSION} \
    && rbenv global ${RUBY_VERSION} \
    && ruby --version \
    && ruby -e "require 'openssl'; puts OpenSSL::VERSION" \
    && gem install bundler -v "${BUNDLER_VERSION}"

# RUN cd /tmp \
#     && echo "Fixing CA certificate issue" \
#     && rubygems=$(gem which rubygems) && global_ca=$(find $(dirname $rubygems) -name "GlobalSignRootC*.pem") \
#     && wget https://raw.githubusercontent.com/rubygems/rubygems/master/lib/rubygems/ssl_certs/rubygems.org/GlobalSignRootCA_R3.pem \
    # && cp GlobalSignRootCA_R3.pem $global_ca \
#RUN wget https://rubygems.org/gems/rubygems-update-${RUBY_VERSION}.gem \
#    && gem install --local rubygems-update-${RUBY_VERSION}.gem \
#    && gem install bundler -v "${BUNDLER_VERSION}"

# Install ccache (we must build for arm64)
ARG CCACHE_VERSION=4.11.3
RUN cd /tmp && wget https://github.com/ccache/ccache/releases/download/v${CCACHE_VERSION}/ccache-${CCACHE_VERSION}.tar.gz \
    && tar xfz ccache-${CCACHE_VERSION}.tar.gz && cd ccache-${CCACHE_VERSION} \
    && mkdir build && cd build && cmake -G Ninja -DCMAKE_BUILD_TYPE=Release .. \
    && ninja && ninja install

# Install specific version of doxygen (eg: 1_10_0). If empty, the step is completely ignored
ARG DOXYGEN_VERSION_UNDERSCORED=1_10_0
RUN if [ -n "${DOXYGEN_VERSION_UNDERSCORED}" ]; then \
      cd /tmp \
      && apt-get -y --no-install-recommends --no-install-suggests install flex bison \
      && wget https://github.com/doxygen/doxygen/archive/refs/tags/Release_${DOXYGEN_VERSION_UNDERSCORED}.tar.gz \
      && tar xfz Release_${DOXYGEN_VERSION_UNDERSCORED}.tar.gz \
      && cd doxygen-Release_${DOXYGEN_VERSION_UNDERSCORED} \
      && mkdir build && cd build && cmake -G Ninja -DCMAKE_BUILD_TYPE=Release .. \
      && ninja && ninja install \
    ; fi

# Install QtIFW to the default directory, but explicitly
ARG QTIFW_VERSION=4.8.1
ARG QTIFW_INSTALL_DIR=${HOME}/Qt/QtIFW-${QTIFW_VERSION}
ENV PATH=${QTIFW_INSTALL_DIR}/bin:${PATH}
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        QTIFW_ARCH="x64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        QTIFW_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi \
    && QTIFW_URL="https://download.qt.io/official_releases/qt-installer-framework/${QTIFW_VERSION}/QtInstallerFramework-linux-${QTIFW_ARCH}-${QTIFW_VERSION}.run" \
    && curl -fsSL -o qtifw.run "${QTIFW_URL}" \
    && chmod +x qtifw.run \
    && apt-get -y install libxkbcommon-x11-0 xorg-dev libgl1-mesa-dev libxcb-icccm4-dev libxcb-image0-dev libxcb-keysyms1-dev libxcb-render-util0-dev libxcb-xinerama0-dev libxcb-randr0-dev libxcb-shape0 libxcb-cursor0 libdbus-1-3 libwebp-dev \
    && ./qtifw.run \
        --accept-licenses \
        --confirm-command \
        --default-answer --root ${HOME}/Qt/QtIFW-${VERSION} install \
    && rm -rf qtifw.run

## Cleanup cached apt data we don't need anymore
RUN apt-get -qq autoremove -y \
    && apt-get -qq autoclean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/*

# create default user ubuntu (added by default already starting at noble), Jenkins uses it
RUN if [ "${VARIANT}" = "focal" ] || [ "${VARIANT}" = "jammy" ]; then useradd -u 1000 ubuntu; fi

COPY .inputrc .bashrc ${HOME}
COPY git-prompt.sh ${HOME}/.config/git/

CMD ["/bin/bash"]
