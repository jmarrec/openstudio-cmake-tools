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
    lcov wget ninja-build gpg-agent software-properties-common ca-certificates \
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

RUN echo "Installing Ruby ${RUBY_VERSION} via RVM" \
    && curl -sSL https://rvm.io/mpapis.asc | gpg --import - \
    && curl -sSL https://rvm.io/pkuczynski.asc | gpg --import - \
    && curl -sSL https://get.rvm.io | bash -s stable \
    && usermod -a -G rvm root \
    && if [ "${VARIANT}" == "focal" ]; then export RUBY_CFLAGS="-DOPENSSL_API_COMPAT=0x30000000L"; fi \
    && /usr/local/rvm/bin/rvm install ${RUBY_VERSION} --with-openssl-dir=/usr/local/ssl/ -- --enable-static \
    && /usr/local/rvm/bin/rvm --default use ${RUBY_VERSION}

ENV PATH="/usr/local/rvm/rubies/ruby-${RUBY_VERSION}/bin:${PATH}"

# RUN cd /tmp \
#     && echo "Fixing CA certificate issue" \
#     && rubygems=$(gem which rubygems) && global_ca=$(find $(dirname $rubygems) -name "GlobalSignRootC*.pem") \
#     && wget https://raw.githubusercontent.com/rubygems/rubygems/master/lib/rubygems/ssl_certs/rubygems.org/GlobalSignRootCA_R3.pem \
    # && cp GlobalSignRootCA_R3.pem $global_ca \
RUN wget https://rubygems.org/gems/rubygems-update-${RUBY_VERSION}.gem \
    && gem install --local rubygems-update-${RUBY_VERSION}.gem \
    && gem install bundler -v "${BUNDLER_VERSION}"

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

## Cleanup cached apt data we don't need anymore
RUN apt-get -qq autoremove -y \
    && apt-get -qq autoclean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/*

# create default user ubuntu
RUN if [ "${VARIANT}" != "noble" ]; then useradd -u 1000 ubuntu; fi;

COPY .inputrc .bashrc ${HOME}
COPY git-prompt.sh ${HOME}/.config/git/

CMD ["/bin/bash"]
