# Docker images for OpenStudio CI

The docker images have build tools such as GCC, conan2, QtIFW, CCACHE, cmake, etc.

It has Python via pyenv and Ruby via rbenv.

With a GHA action that will push multi-platform images with proper versioning to Dockerhub.

The GHA action makes use of the ubuntu-24.04-arm64 runner so it doesn't have to use QEMU (which speeds the build from about 5 hours to 18min)
