import os.path
import requests
from xml.etree import ElementTree

# MAIN_URL = "https://atom.cuzk.cz/DMR5G-SJTSK/DMR5G-SJTSK.xml"
MAIN_URL = "https://atom.cuzk.cz/DMR5G-SJTSK/OSD-DMR5G-SJTSK.xml"
REG_FILE = "/tmp/dmr5g-atom.xml"
FRAGMENT_FILE = "dmr5g-fragments.txt"
FRAGMENT_OUTPUT_DIR = "output"

def get_tag(child):
    return child.tag.split("}")[1]

def parse_registry():
    if not os.path.isfile(REG_FILE):
        # Download registry file
        response = requests.get(MAIN_URL)
        if response.status_code != 200:
            print("Error: Could not get the data registry")
            exit(1)
        registry = response.content
        with open(REG_FILE, "wb") as f:
            f.write(registry)
        root = ElementTree.fromstring(registry)
    else:
        # Load registry file
        with open(REG_FILE, "rb") as f:
            tree = ElementTree.parse(f)
            root = tree.getroot()

    frag_f = open(FRAGMENT_FILE, "w")
    for child in root:
        if child.tag == "Query":
            for a in child.attrib:
                if "spatial_dataset_identifier_code" in a:
                    part_url = child.attrib[a]
                    response = requests.get(part_url)
                    if response.status_code != 200:
                        print("Error: Could not get the data registry")
                        exit(1)
                    subroot = ElementTree.fromstring(response.content)
                    for subchild in subroot:
                        if get_tag(subchild) == "entry":
                            for el in subchild:
                                if get_tag(el) == "link":
                                    frag_f.write(el.attrib["href"] + "\n")
    frag_f.close()

def download_fragments():
    if not os.path.isdir(FRAGMENT_OUTPUT_DIR):
        os.mkdir(FRAGMENT_OUTPUT_DIR)
    with open(FRAGMENT_FILE, "r") as frag_f:
        for l in frag_f.readlines():
            l = l.strip()
            filename = l.split("/")[-1]
            filepath = os.path.join(FRAGMENT_OUTPUT_DIR, filename)
            print(f"⬇️  Downloading {filename}")
            response = requests.get(l)
            if response.status_code != 200:
                print("Error: Could not get the data registry")
                exit(1)
            with open(filepath, "wb") as output_f:
                output_f.write(response.content)
            print(f"  ✅ Done")

if __name__ == "__main__":
    if os.path.isfile(FRAGMENT_FILE):
        print("Fragment file already exists. Press any key to start downloading...")
    else:
        print("Building fragment file. This may take minutes.")
        parse_registry()
        print("Fragment file built. Press any key to start downloading...")
    input()
    download_fragments()


    