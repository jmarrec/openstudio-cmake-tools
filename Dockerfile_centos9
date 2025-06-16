FROM almalinux:9

USER root
ENV HOME="/home/root"
WORKDIR ${HOME}

ENV TZ=US
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

#RUN useradd -m oscentos
#USER oscentos

# Chained into a single run statement to mimize the number of image layers
# The perl-Data-Dumper / perl-Thread-Queue are so you can build swig correctly, perl-IPC-Cmd perl-FindBin  perl-Pod-Html needed for openssl
# epel-release allows me to find lsb_release
# Lots of EPEL packages since the PowerTools/CRB repository for developers, such as glibc-static
RUN dnf clean all && dnf -y update \
 && dnf install -y epel-release dnf-plugins-core \
 && dnf config-manager --set-enabled crb \
 && dnf group install -y "Development Tools" \
 && dnf install -y lsb_release glibc-static gcc-gfortran libgfortran-static libstdc++-static \
    zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel tk-devel libffi-devel xz-devel openssl-devel \
    autoconf gcc patch bzip2 openssl-devel libffi-devel readline zlib-devel gdbm ncurses-devel tar libyaml-devel \
    perl-Data-Dumper perl-Thread-Queue perl-Digest-SHA1 perl-Digest-SHA perl-IPC-Cmd perl-FindBin perl-Pod-Html \
    lcov aria2 wget ninja-build gnupg2 ca-certificates pkgconf \
    jq p7zip p7zip-plugins tree bash-completion ripgrep tmate vim \
    groff less \
    libglvnd-devel mesa-libGL-devel.x86_64 mesa-libGLU-devel.x86_64 mesa-libGLw.x86_64 mesa-libGLw-devel.x86_64 libXi-devel.x86_64 freeglut-devel.x86_64 freeglut.x86_64                 libXrandr libXrandr-devel libXinerama-devel libXcursor-devel \
 && ARCH=$(uname -m) && \
 if [ "$ARCH" = "x86_64" ]; then \
     CLI_ZIP="awscli-exe-linux-x86_64.zip"; \
 elif [ "$ARCH" = "aarch64" ]; then \
     CLI_ZIP="awscli-exe-linux-aarch64.zip"; \
 else \
     echo "Unsupported architecture: $ARCH" && exit 1; \
 fi \
 && cd /tmp \
 && curl "https://awscli.amazonaws.com/${CLI_ZIP}" -o "awscliv2.zip" \
 && unzip awscliv2.zip \
 && ./aws/install

# Set the locale
RUN dnf install -y glibc-langpack-en \
 && echo 'LANG=en_US.UTF-8' > /etc/locale.conf

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    GTEST_COLOR=1 \
    CMAKE_EXPORT_COMPILE_COMMANDS=ON \
    NINJA_STATUS="[%p][%f/%t] "

# Setup the GitHub CLI
RUN dnf install -y dnf-plugins-core \
 && dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo \
 && dnf install -y gh

 # Install cmake
ARG CMAKE_VERSION=4.0.3
RUN cd /tmp && curl -fsSL -o cmake.sh https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).sh \
 && chmod +x cmake.sh \
 && mkdir -p /usr/local/cmake \
 && ./cmake.sh --skip-license --prefix=/usr/local/cmake \
 && ln -sf /usr/local/cmake/bin/cmake /usr/local/bin/cmake

# Install python from pyenv
ARG PYTHON_VERSION=3.12.2
# NOTE: We're placing pyenv and rbenv at /opt/ instead of $HOME/.pyenv, because the entire HOME directory is bind-mounted on CI, so it would be obscured by the mount
ENV PYENV_ROOT=/opt/pyenv \
    PATH=/opt/pyenv/versions/${PYTHON_VERSION}/bin:/opt/pyenv/shims:/opt/pyenv/bin:${PATH} \
    Python_ROOT_DIR=/opt/pyenv/versions/${PYTHON_VERSION} \
    PYTHON_VERSION=${PYTHON_VERSION}

# RUN dnf install -y zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel tk-devel libffi-devel xz-devel openssl-devel \
RUN curl https://pyenv.run | bash \
    && PYTHON_CONFIGURE_OPTS="--enable-shared" pyenv install ${PYTHON_VERSION} \
    && pyenv global ${PYTHON_VERSION} \
    && pip install -q --upgrade --no-cache-dir pip setuptools

# Install conan (and configure) and some packages
RUN python --version \
    && pip install "conan==2.17.0" gcovr "pandas==2.2.3" "numpy==2.0.2" "pytest==8.3.3" pytest-xdist twine requests packaging "tabulate==0.9.0" \
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
    PATH=/opt/rbenv/versions/${RUBY_VERSION}/bin:/opt/rbenv/shims:/opt/rbenv/bin:${PATH}

# Install ruby via rbenv
# https://github.com/rbenv/ruby-build/wiki#rhelcentos
# and even RUBY_BUILD_VENDOR_OPENSSL=1. I don't think we care about the openssl version used anymore (our conan ruby is used for building)
# rbenv-installer does not allow specifying the PATH where it's going to be installed
# RUN dnf install -y autoconf gcc patch bzip2 openssl-devel libffi-devel readline zlib-devel gdbm ncurses-devel tar perl-FindBin libyaml-devel \
RUN git clone https://github.com/rbenv/rbenv.git ${RBENV_ROOT} \
    && git clone https://github.com/rbenv/ruby-build.git $RBENV_ROOT/plugins/ruby-build \
    && rbenv init bash \
    && RUBY_CONFIGURE_OPTS="--disable-shared" rbenv install -v ${RUBY_VERSION} \
    && rbenv global ${RUBY_VERSION} \
    && ruby --version \
    && ruby -e "require 'openssl'; puts OpenSSL::VERSION" \
    && gem install bundler -v "${BUNDLER_VERSION}" \
    && echo "Shenanigans to fix the bundle tests" \
    && mkdir -p /opt/rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/gems/bundler-2.4.10/libexec \
    && ln -sf ../exe/bundle /opt/rbenv/versions/3.2.2/lib/ruby/gems/3.2.0/gems/bundler-2.4.10/libexec/bundle

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
      && wget https://github.com/doxygen/doxygen/archive/refs/tags/Release_${DOXYGEN_VERSION_UNDERSCORED}.tar.gz \
      && tar xfz Release_${DOXYGEN_VERSION_UNDERSCORED}.tar.gz \
      && cd doxygen-Release_${DOXYGEN_VERSION_UNDERSCORED} \
      && mkdir build && cd build && cmake -G Ninja -DCMAKE_BUILD_TYPE=Release .. \
      && ninja && ninja install \
    ; fi

# Install QtIFW to the default directory, but explicitly
ARG QTIFW_VERSION=4.8.1
ARG QTIFW_INSTALL_DIR=/opt/Qt/QtIFW-${QTIFW_VERSION}
ENV PATH=${QTIFW_INSTALL_DIR}/bin:${PATH}
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        QTIFW_ARCH="x64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        QTIFW_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi \
    && cd /tmp \
    && QTIFW_URL="https://download.qt.io/official_releases/qt-installer-framework/${QTIFW_VERSION}/QtInstallerFramework-linux-${QTIFW_ARCH}-${QTIFW_VERSION}.run" \
    && curl -fsSL -o qtifw.run "${QTIFW_URL}" \
    && chmod +x qtifw.run \
    && dnf install -y libxkbcommon-x11-devel xcb-util-cursor-devel xcb-util-wm-devel xcb-util-keysyms-devel \
    && ln -sf /usr/lib64/libbz2.so /usr/lib64/libbz2.so.1.0 \
    && ./qtifw.run \
        --accept-licenses \
        --confirm-command \
        --default-answer --root ${QTIFW_INSTALL_DIR} install

# Clean up cached dnf data we don't need anymore
RUN dnf -y autoremove \
    && dnf clean all \
    && rm -rf /var/cache/dnf \
    && rm -rf /tmp/*

# create default user
RUN useradd -u 1000 oscentos

COPY .inputrc .bashrc ${HOME}
COPY git-prompt.sh ${HOME}/.config/git/
COPY report_tool_infos.py /usr/local/bin/report_tool_infos

# Make another copy at /opt/config
COPY .inputrc .bashrc /opt/config/
COPY git-prompt.sh /opt/config/

CMD ["/bin/bash"]
