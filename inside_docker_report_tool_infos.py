import os
import re
import subprocess
import shutil

import pandas as pd

RE_VERSION = re.compile(r"(\d+\.\d+\.\d+)")

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


def get_path_variable() -> str:
    return os.environ["PATH"]


def report_tool_infos() -> list[dict[str, str]]:
    tool_infos = []
    for tool_name in TOOLS:
        tool_path = shutil.which(cmd=tool_name)
        version = subprocess.check_output([tool_name, "--version"], universal_newlines=True, encoding="utf-8").split(
            "\n"
        )[0]
        m = RE_VERSION.search(version)
        assert version, f"Failed to match a version for {tool_name}: {version}"
        tool_infos.append({"name": tool_name, "path": tool_path, "version": m.groups()[0]})
    return tool_infos


if __name__ == "__main__":
    path_infos = get_path_variable().split(":")
    print("## PATH variable:\n")
    print(pd.DataFrame(path_infos, columns=["PATH entry"]).to_markdown(index=False))

    print("\n## Tool versions:\n")
    tool_infos = report_tool_infos()
    print(pd.DataFrame(tool_infos).to_markdown(index=False))
