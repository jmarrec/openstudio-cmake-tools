import argparse
import re
import subprocess
from enum import StrEnum

import pandas as pd

IMAGE_NAME = "jmarrec/openstudio-cmake-tools"
IMAGE_TAGS = [
    "ubuntu-20.04-v1",
    "ubuntu-22.04-v1",
    "ubuntu-24.04-v1",
]


class Platform(StrEnum):
    AMD64 = "linux/amd64"
    ARM64 = "linux/arm64"


RE_VERSION = re.compile(r"(\d+\.\d+\.\d+)")

DEFAULT_CONTAINER_NAME = "temp"


def pull_latest_image(image_name: str, platform: Platform = Platform.AMD64, verbose: bool = False):
    cmd_args = ["docker", "pull", "--platform", platform, image_name]
    if verbose:
        print(f"Pulling latest image: {' '.join(cmd_args)}")
    subprocess.check_call(cmd_args)


def start_container(
    image_name: str,
    container_name: str = DEFAULT_CONTAINER_NAME,
    platform: Platform = Platform.AMD64,
    verbose: bool = False,
):
    # This is similar to `docker run --name temp -d -it --rm jmarrec/openstudio-cmake-tools:ubuntu-24.04-v1 /bin/bash > /dev/stdout`
    cmd_args = [
        "docker",
        "run",
        "--platform",
        platform,
        "--name",
        container_name,
        "-d",  # detached
        image_name,
        "tail",
        "-f",
        "/dev/null",  # keeps it alive
    ]
    if verbose:
        print(f"Starting container: {' '.join(cmd_args)}")

    subprocess.check_call(cmd_args)


def stop_container(container_name: str = DEFAULT_CONTAINER_NAME, verbose: bool = False):
    cmd_args = ["docker", "rm", "-f", "temp"]
    if verbose:
        print(f"Stopping container: {' '.join(cmd_args)}")
    subprocess.check_call(cmd_args)


def get_path_variable(container_name: str = DEFAULT_CONTAINER_NAME, platform: Platform = Platform.AMD64) -> str:
    return subprocess.check_output(
        ["docker", "exec", container_name, "bash", "-c", "echo $PATH"], universal_newlines=True, encoding="utf-8"
    ).strip()


TOOLS = [
    "cmake",
    "pyenv",
    "python",
    "conan",
    "rbenv",
    "ruby",
    "bundler",
    "archivegen",
    "ruby",
    "doxygen",
    "ccache",
    "gcc",
]


def report_tool_infos(container_name) -> list[dict[str, str]]:
    tool_infos = []
    for tool_name in TOOLS:
        tool_path = subprocess.check_output(
            ["docker", "exec", container_name, "which", tool_name], universal_newlines=True, encoding="utf-8"
        ).strip()
        version = subprocess.check_output(
            ["docker", "exec", container_name, tool_name, "--version"], universal_newlines=True, encoding="utf-8"
        ).split("\n")[0]
        m = RE_VERSION.search(version)
        assert version, f"Failed to match a version for {tool_name}: {version}"
        tool_infos.append({"name": tool_name, "path": tool_path, "version": m.groups()[0]})
    return tool_infos


if __name__ == "__main__":

    parser = argparse.ArgumentParser(description="Inspect Docker containers for tool versions and PATHs")
    parser.add_argument("--platform", choices=[x for x in Platform], default=Platform.AMD64, help="Target platform")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output")
    parser.add_argument("--pull", action="store_true", help="Pull latest image before inspecting")

    args = parser.parse_args()
    platform = args.platform
    verbose = args.verbose
    do_pull = args.pull

    path_infos = {}
    all_tool_infos = {}
    for image_tag in IMAGE_TAGS:
        image_name = f"{IMAGE_NAME}:{image_tag}"
        if do_pull:
            pull_latest_image(image_name=image_name, platform=platform, verbose=verbose)
        container_name = DEFAULT_CONTAINER_NAME
        start_container(image_name=image_name, container_name=container_name, platform=platform, verbose=verbose)
        path_infos[image_tag] = get_path_variable(container_name=container_name).split(":")
        all_tool_infos[image_tag] = report_tool_infos(container_name=container_name)
        stop_container(container_name=container_name, verbose=verbose)

    print("\n## PATH variable:\n")
    print(pd.DataFrame(path_infos).to_markdown(index=False))

    print("\n## Tool versions:\n")
    print(
        pd.concat(
            {k: pd.DataFrame(v).set_index(["name", "path"])["version"] for k, v in all_tool_infos.items()}, axis=1
        )
        .reset_index()
        .to_markdown(index=False)
    )
