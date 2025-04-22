#! /usr/bin/env python3

import os
import re
import subprocess
import argparse

cluster_name = ""
cluster_url= ""

confg_dir = os.listdir("config/");

parser = argparse.ArgumentParser(description="This utility is used to generate control plane configs for talos.");
parser.add_argument('cluster_name')
parser.add_argument('cluster_url')

args = parser.parse_args();

for path in confg_dir:
  if re.search('talos-ctrl-[0-9]+', path):
    subprocess.run(["talosctl", "gen", "config",
                    f"{args.cluster_name}", 
                    f"{args.cluster_url}",
                    "--with-secrets", "./secrets.yaml", 
                    "--config-patch", "@config/control-plane-common.yaml",
                    "--config-patch-control-plane", f"@config/{path}",
                    "--output-types", "controlplane", 
                    "--output", f"temp/{path}",
                    "--force"])
