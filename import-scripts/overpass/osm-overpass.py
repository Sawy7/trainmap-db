import config
import psycopg2
import requests
import sys
from tqdm import tqdm

class RailLine:
    def __init__(self):
        self.points = []
    
    def add_point(self, lat, lon):
        self.points.append((lat, lon))

    def get_geom(self):
        geom = "ST_MakeLine(ARRAY["
        for p in self.points:
            geom += f"ST_SetSRID(ST_Point({p[1]},{p[0]}),4326),"
        geom = geom[:-1]+ "])"
        return geom

    def make_insert(self, relnum, conn):
        geom = self.get_geom()
        
        cur = conn.cursor()
        cur.execute(f"INSERT INTO osm_rails (relcislo, geom) VALUES (%s, {geom});", (relnum, ))
        conn.commit()
        cur.close()

class RailMultiLine:
    def __init__(self):
        self.lines = []

    def add_line(self, line):
        self.lines.append(line)

    def parse_ways(self, ways_array):
        for way in ways_array:
            line = RailLine()
            if way["type"] != "way":
                print("WARN: This is not a way, yet it is in a parsing loop")
                continue
            for point in way["geometry"]:
                line.add_point(point["lat"], point["lon"])
            self.add_line(line)

    def make_insert(self, relnum, conn):
        for l in self.lines:
            l.make_insert(relnum, conn)

class AllRails:
    def __init__(self):
        self.conn = psycopg2.connect(
            database=config.DBNAME, user=config.DBUSER,
            password=config.DBPASS, host=config.DBHOST,
            port=config.DBPORT
        )

    def destroy(self):
        self.conn.close()

    def init_db(self):
        self.create_tables()
        self.create_index()

    def create_tables(self):
        cur = self.conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS "osm_data_index" (
                relcislo int PRIMARY KEY,
                id varchar(6),
                nazevtrasy varchar(200)
            );""")
        cur.execute("""
            CREATE TABLE IF NOT EXISTS "osm_rails" (
                gid serial PRIMARY KEY,
                relcislo int,
                geom geometry('LINESTRING', 4326, 2),
                CONSTRAINT fk_relcislo_osm
                    FOREIGN KEY(relcislo)
                        REFERENCES osm_data_index(relcislo)
            );""")
        self.conn.commit()
        cur.close()
        
    def create_index(self):
        cur = self.conn.cursor()
        cur.execute("CREATE INDEX IF NOT EXISTS osm_rails_geom_idx ON osm_rails USING GIST (geom)")
        self.conn.commit()
        cur.close()

    def run(self):
        # Getting the parent relation
        print("Downloading all railways in CZ (this may take a while...) ⏳")
        parent = self.get_relation(config.ALL_RAILS_RELATION)
        for i,e in enumerate(tqdm(parent["members"])):
            # Skip existing
            if self.check_if_index_exists(e["ref"]):
                continue

            # Skip abandoned
            ways = self.get_relation_ways(e["ref"])
            if "abandoned" in ways["tags"] and ways["tags"]["abandoned"] == "yes":
                continue

            
            multiline = RailMultiLine()
            multiline.parse_ways(ways["members"])

            # Unify ref properties
            if "ref" not in ways["tags"] or ways["tags"]["ref"] == "-":
                ways["tags"]["ref"] = None
            elif " " in ways["tags"]["ref"]:
                ways["tags"]["ref"] = int(ways["tags"]["ref"].replace(" ", ""))

            # Final insert
            self.insert_rail(ways["tags"]["ref"], e["ref"], ways["tags"]["name"], multiline)
        print("Done! ✅")

    def get_relation(self, id):
        response = requests.get(url=f"{config.STATIC_API}/relation/{id}.json")
        if response.status_code == 200:
            return response.json()["elements"][0]
        else:
            return self.get_relation(id)

    def check_if_index_exists(self, id):
        cur = self.conn.cursor()
        cur.execute("SELECT * FROM osm_data_index WHERE relcislo = %s;", (id, ))
        row_count = cur.rowcount
        cur.close()
        return row_count > 0

    def get_relation_ways(self, id):
        query = f"""
            [out:json];
            (
                relation({id});
            );
            out geom;
        """
        response = requests.post(url=config.OVERPASS_API, data=query)
        if response.status_code == 200:
            return response.json()["elements"][0]
        else:
            return self.get_relation_ways(id)

    def insert_rail(self, num, relnum, name, ml):
        # Insert index
        cur = self.conn.cursor()
        cur.execute("INSERT INTO osm_data_index (id, relcislo, nazevtrasy) VALUES (%s, %s, %s);",
                    (num, relnum, name))
        self.conn.commit()
        cur.close()

        # Insert rail
        ml.make_insert(relnum, self.conn)

class AllWays:
    def __init__(self):
        self.conn = psycopg2.connect(
            database=config.DBNAME, user=config.DBUSER,
            password=config.DBPASS, host=config.DBHOST,
            port=config.DBPORT
        )

    def init_db(self):
        self.create_tables()
        self.create_index()

    def create_tables(self):
        cur = self.conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS "osm_ways" (
                id integer PRIMARY KEY,
                electrified varchar(20),
                voltage integer,
                gauge varchar(20),
                maxspeed integer,
                tracks integer,
                usage varchar(20),
                geom geometry('LINESTRING', 4326, 2)
            );""")
        self.conn.commit()
        cur.close()
        
    def create_index(self):
        cur = self.conn.cursor()
        cur.execute("CREATE INDEX IF NOT EXISTS osm_ways_geom_idx ON osm_ways USING GIST (geom)")
        self.conn.commit()
        cur.close()

    def destroy(self):
        self.conn.close()

    def get_all_ways(self):
        query = f"""
            [out:json];
            area[admin_level=2]["ISO3166-1"="CZ"]->.country;
            (
            way(area.country)
            ["railway"="rail"];
            );
            out geom;
        """
        response = requests.post(url=config.OVERPASS_API, data=query)
        if response.status_code == 200:
            return response.json()["elements"]
        else:
            print(f"Retrying 🔄")
            return self.get_all_ways()

    def get_existing_way_ids(self):
        cur = self.conn.cursor()
        cur.execute("SELECT id FROM osm_ways;")
        to_return = [x[0] for x in cur.fetchall()]
        cur.close()
        return to_return

    def prepare_way(self, way):
        to_return = {"id": way["id"], "tags": {}, "geom": []}
        for t in way["tags"]:
            if t in config.WAY_PROPS:
                to_return["tags"][t] = way["tags"][t]
        geom_line = RailLine()
        for p in way["geometry"]:
            geom_line.add_point(p["lat"], p["lon"])
        to_return["geom"] = geom_line.get_geom()
        return to_return

    def prepare_insert_way_sql(self, prepared_way):
        columns = "id, geom"
        values = f"{prepared_way['id']}, {prepared_way['geom']}"
        for t in prepared_way["tags"]:
            columns += f", {t}"
            values += f", '{prepared_way['tags'][t]}'"
        return f"INSERT INTO osm_ways ({columns}) VALUES ({values});"

    def insert_multiple_ways(self, prepared_ways):
        sql = ""
        for pw in prepared_ways:
            sql += self.prepare_insert_way_sql(pw)
        cur = self.conn.cursor()
        cur.execute(sql)
        self.conn.commit()
        cur.close()

    def run(self):
        print(f"Downloading all ways in CZ (this may take a while...) ⏳")
        ways = self.get_all_ways()
        existing_way_ids = self.get_existing_way_ids()
        prepared_ways = []
        print(f"Preparing for insert ⏳")
        for w in tqdm(ways):
            if int(w["id"]) in existing_way_ids:
                continue
            prepared_ways.append(self.prepare_way(w))
        print(f"Inserting ⏳")
        if len(prepared_ways) > 0:
            self.insert_multiple_ways(prepared_ways)
        print("Done! ✅")

class AllStations:
    def __init__(self):
        self.conn = psycopg2.connect(
            database=config.DBNAME, user=config.DBUSER,
            password=config.DBPASS, host=config.DBHOST,
            port=config.DBPORT
        )

    def destroy(self):
        self.conn.close()

    def init_db(self):
        self.create_tables()
        self.create_index()

    def create_tables(self):
        cur = self.conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS "all_stations" (
                id numeric PRIMARY KEY,
                name varchar(254),
                geom geometry('POINT', 4326, 2)
            );""")
        self.conn.commit()
        cur.close()
        
    def create_index(self):
        cur = self.conn.cursor()
        cur.execute("CREATE INDEX IF NOT EXISTS all_stations_geom_idx ON all_stations USING GIST (geom)")
        self.conn.commit()
        cur.close()

    def parse_elements(self, elements):
        # NOTE: This could get more, if needed (probably mostly useless tags)
        print(f"Parsing downloaded data ⏳")
        parsed = []
        for e in tqdm(elements):
            if "id" in e and "tags" in e and "name" in e["tags"]:
                parsed.append({
                    "id": int(e["id"]),
                    "name": e["tags"]["name"],
                    "geom": f"ST_Point({e['lon']}, {e['lat']})"
                })
        return parsed

    def insert_multiple_stations(self, parsed_elements):
        sql = "INSERT INTO all_stations (id, name, geom) VALUES "
        for i,e in enumerate(parsed_elements):
            if i > 0:
                sql += ", "
            sql += f"({e['id']}, '{e['name']}', {e['geom']})"
        sql += " ON CONFLICT (id) DO NOTHING"
        cur = self.conn.cursor()
        cur.execute(sql)
        self.conn.commit()
        cur.close()

    def delete_duplicates(self):
        cur = self.conn.cursor()
        cur.execute("""
            DELETE FROM all_stations AS a
            WHERE EXISTS (
                SELECT 1
                FROM all_stations AS b
                WHERE (a.name = b.name OR ST_DWithin(a.geom, b.geom, 0.001))
                AND a.id > b.id
            );""")
        self.conn.commit()
        cur.close()

    def run(self):
        print(f"Downloading stations/halts/stops in CZ (this may take a while...) ⏳")
        query = f"""
            [out:json];
            area[admin_level=2]["ISO3166-1"="CZ"]->.country;
            (
            node(area.country)
            ["railway"="station"];
            node(area.country)
            ["railway"="halt"];
            node(area.country)
            ["railway"="stop"];
            );
            out;
        """
        response = requests.post(url=config.OVERPASS_API, data=query)
        if response.status_code == 200:
            elements = response.json()["elements"]
            parsed_elements = self.parse_elements(elements)
            print("Inserting queued stations ⏳️")
            self.insert_multiple_stations(parsed_elements)
            self.delete_duplicates()
        else:
            print(f"Retrying 🔄")
            return self.run()
        print("Done! ✅")

def run_rails():
    all_rails = AllRails()
    all_rails.init_db()
    all_rails.run()
    all_rails.destroy()

def run_ways():
    all_ways = AllWays()
    all_ways.init_db()
    all_ways.run()
    all_ways.destroy()

def run_stations():
    all_stations = AllStations()
    all_stations.init_db()
    all_stations.run()
    all_stations.destroy()

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ["-a", "--all"]:
        run_rails()
        run_ways()
        run_stations()
        exit(0)

    print("🤖 What do you want to do? Please enter your choice and press enter:")
    print("  1️⃣  Download all railways in Czech Republic (numbered and catalogued) and save them to DB")
    print("  2️⃣  Download all ways in Czech Republic (individual rail pieces with metadata) and save them to DB")
    print("  3️⃣  Download stations/halts/stops in Czech Republic and save them to DB")
    print("✏️  Your choice: ", end="", flush=True)
    try:
        choice = int(input())
    except:    
        print("Invalid choice. Exiting...")
        exit(1)
    print()

    if choice == 1:
        run_rails()
    elif choice == 2:
        run_ways()
    elif choice == 3:
        run_stations()
    else:
        print("Invalid choice. Exiting...")
        exit(1)