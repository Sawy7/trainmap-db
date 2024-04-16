import os.path
import requests
from requests.adapters import HTTPAdapter
from requests_futures.sessions import FuturesSession
from urllib3.util import Retry
from urllib3.exceptions import MaxRetryError
from concurrent.futures import as_completed
from xml.etree import ElementTree
import sys
from tqdm import tqdm
from itertools import islice

# MAIN_URL = "https://atom.cuzk.cz/DMR5G-SJTSK/DMR5G-SJTSK.xml"
MAIN_URL = "https://atom.cuzk.cz/DMR5G-SJTSK/OSD-DMR5G-SJTSK.xml"
REG_FILE = "/tmp/dmr5g-atom.xml"
FRAGMENT_FILE = "dmr5g-fragments.txt"
FRAGMENT_OUTPUT_DIR = "output"

def get_tag(child):
    return child.tag.split("}")[1]

def parse_registry():
    print("Downloading the registry index ⏳️")
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
    print("Extracting individual URLs (this may take a while...) ⏳️")
    for child in tqdm(root):
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
    print("✅ Done!")

def download_fragments():
    if not os.path.isdir(FRAGMENT_OUTPUT_DIR):
        os.mkdir(FRAGMENT_OUTPUT_DIR)
    retries = Retry(total=5, backoff_factor=1, status_forcelist=[ 502, 503, 504 ])
    adapter = HTTPAdapter(max_retries=retries)
    session = requests.Session()
    session.mount('http://', adapter)
    session.mount('https://', adapter)
    future_session = FuturesSession(session=session)
    print("Downloading all the individual fragments (this may take a while...) ⏳️")
    with open(FRAGMENT_FILE, "r") as frag_f:
        all_urls = [l.strip() for l in frag_f.readlines()]
        with tqdm(total=len(all_urls)) as pbar:
            iter_urls = iter(all_urls)
            while True:
                url_chunk = list(islice(iter_urls, 100))
                if not url_chunk:
                    break
                url_chunk_new = []
                for url in url_chunk:
                    filename = url.split("/")[-1]
                    filepath = os.path.join(FRAGMENT_OUTPUT_DIR, filename)
                    if os.path.isfile(filepath):
                        pbar.update(1)
                    else:
                        url_chunk_new.append(url)
                if not url_chunk_new:
                    continue
                futures = [future_session.get(url) for url in url_chunk_new]
                for future in as_completed(futures):
                    try:
                        response = future.result()
                    except MaxRetryError:
                        print("Error: Could not download the fragment (Max retries exceeded)")
                        exit(1)
                    filename = response.request.url.split("/")[-1]
                    filepath = os.path.join(FRAGMENT_OUTPUT_DIR, filename)
                    if response.status_code != 200:
                        print("Error: Could not get the data registry")
                        exit(1)
                    with open(filepath, "wb") as output_f:
                        output_f.write(response.content)
                    pbar.update(1)

if __name__ == "__main__":
    if os.path.isfile(FRAGMENT_FILE):
        print("Fragment file already exists. Press any key to start downloading... ⌨️")
    else:
        print("Fragment file not found. Will build! ✏️")
        parse_registry()
        print("Fragment file built. Press any key to start downloading... ⌨️")
    if len(sys.argv) == 1 or sys.argv[1] != "-y":
        input()
    download_fragments()