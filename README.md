# 💾 Mapster DB
> Tento repositář si klade za cíl popsat aktuální stav aplikační databáze a ukázat, jak takovou databázi vytvořit.

## 🐋 Doporučená metoda
Pro vytvoření čerstvé kopie databáze, tzv. *from scratch* byl připraven Docker kontejner. Takové sestavení může v závislosti na výkonu hostitelského stroje a kapacitě internetového připojení trvat relativně dlouho dobu, ale proces je zcela automatizovaný, takže za normálního chodu není potřeba s ním interagovat.

### Postup

```console
git clone https://gitlab.vsb.cz/centrum-enet-inf/enet-sz-mapdb.git
cd auto-db
chmod +x *.sh
./create.sh
sudo docker exec -it trainmap-db /data/bootstrap.sh
```


## 🧰 Manuální metoda
Celý postup pro manuální vytvoření databáze je popsán v souboru [manual-init.md](manual-init.md). Sestavovat databázi takto "interaktivním" způsobem není doporučeno a dokument slouží zejména pro úplnost dokumentace.