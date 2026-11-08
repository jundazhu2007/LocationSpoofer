# Third-party notices

## OpenFlights data

`Resources/airports.tsv` and `Resources/routes.txt` are derived from the
[OpenFlights](https://openflights.org/data.html) airport and route databases.

- Source: <https://github.com/jpatokal/openflights>
- License: [Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/)
- Contents of the database: [Database Contents License](https://opendatacommons.org/licenses/dbcl/1-0/)

The derived files keep only airports with scheduled service and non-stop
(zero-stop) routes. They are redistributed under the ODbL; if you modify and
publicly use them, you must attribute OpenFlights and share the derived
database under the same license. The application source code is MIT licensed
(see `LICENSE`); the ODbL applies to the data files only.

Route and airport data may be incomplete or out of date.

## Map data

Maps, search and directions are provided by Apple MapKit at runtime and are
subject to Apple's terms. No map data is bundled with this repository.
