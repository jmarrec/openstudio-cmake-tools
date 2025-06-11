import re
import subprocess

import pandas as pd

IMAGE_NAME = "jmarrec/openstudio-cmake-tools"
IMAGE_TAGS = [
    "ubuntu-20.04-v1",
    "ubuntu-22.04-v1",
    "ubuntu-24.04-v1",
]

RE_VERSION = re.compile(r"(\d+\.\d+\.\d+)")

DEFAULT_CONTAINER_NAME = "temp"


def pull_latest_image(image_name):
    subprocess.check_call(["docker", "pull", image_name])


def start_container(image_name, container_name=DEFAULT_CONTAINER_NAME):
    # This is similar to `docker run --name temp -d -it --rm jmarrec/openstudio-cmake-tools:ubuntu-24.04-v1 /bin/bash > /dev/stdout`
    subprocess.check_call(
        [
            "docker",
            "run",
            "--name",
            container_name,
            "-d",  # detached
            image_name,
            "tail",
            "-f",
            "/dev/null",  # keeps it alive
        ]
    )


def stop_container(container_name=DEFAULT_CONTAINER_NAME):
    subprocess.check_call(["docker", "rm", "-f", "temp"])


def get_path_variable(container_name=DEFAULT_CONTAINER_NAME):
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


def report_tool_infos(container_name):
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

    path_infos = {}
    all_tool_infos = {}
    for image_tag in IMAGE_TAGS:
        image_name = f"{IMAGE_NAME}:{image_tag}"
        pull_latest_image(image_name=image_name)
        container_name = "temp"
        start_container(image_name=image_name, container_name=container_name)
        path_infos[image_tag] = get_path_variable(container_name=container_name).split(":")
        all_tool_infos[image_tag] = report_tool_infos(container_name=container_name)
        stop_container(container_name=container_name)

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
