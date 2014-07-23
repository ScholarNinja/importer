importer
========

Imports knowledge about links between papers and software into a graph database

## Seeding with Europe PMC data

This will download all of the zipped big XMLs from Europe PMC (if you have GNU sed):
````
curl -s http://europepmc.org/ftp/oa/ | grep "href=\"PMC" | sed -r 's/.+a href\="(.+.xml.gz)\".+/http:\/\/europepmc.org\/ftp\/oa\/\1/' | xargs wget
```
