# hetzner-dyndns

Ein minimalistischer DynDNS-Client für **Hetzner DNS**. Der Container ermittelt regelmäßig die öffentliche IPv4-Adresse des Hosts und aktualisiert einen A-Record in einer Hetzner-DNS-Zone, falls sich die IP geändert hat.

## Features

- Aktualisiert einen A-Record (IPv4) automatisch über die [Hetzner DNS API](https://dns.hetzner.com/api-docs)
- Lokaler IP-Cache – ruft die Hetzner API nur auf, wenn sich die IP tatsächlich geändert hat (schont das Rate-Limit)
- Lock-Mechanismus verhindert parallele Läufe
- Health-Check-Endpoint über einen eingebauten Mini-Webserver (Port `22222`)
- Läuft als schlanker Alpine-Container, prüft alle 5 Minuten

## Voraussetzungen

- Eine Domain, deren DNS bei Hetzner (Hetzner DNS Console) verwaltet wird
- Ein API-Token aus der [Hetzner DNS Console](https://dns.hetzner.com/settings/api-token)
- Der Ziel-Record (z.B. `vpn.example.com` oder `@`) muss **einmalig manuell** in der Hetzner-DNS-UI angelegt werden – das Script legt keine neuen Records an, es aktualisiert nur bestehende
- Docker & Docker Compose

## Installation

```bash
git clone <repo-url>
cd hetzner-dyndns
cp .env.example .env
# .env mit eigenen Werten befüllen (siehe unten)
docker compose up -d --build
```

## Konfiguration (`.env`)

| Variable | Pflicht | Beschreibung | Beispiel |
|---|---|---|---|
| `HETZNER_TOKEN` | ja | API-Token aus der Hetzner DNS Console | `abcdef123...` |
| `ZONE` | ja | Name der DNS-Zone | `example.com` |
| `RECORD_NAME` | ja | Name des zu aktualisierenden Records innerhalb der Zone | `vpn` (für `vpn.example.com`) oder `@` (für die Zone selbst) |
| `TYPE` | ja | Record-Typ, aktuell nur `A` (IPv4) unterstützt | `A` |
| `TTL` | nein | TTL des Records in Sekunden (Default: `60`) | `60` |
| `API` | nein | Basis-URL der Hetzner API (Default: `https://api.hetzner.cloud/v1`) | – |
| `IPV4_CHECK_URL` | nein | Dienst zur Ermittlung der eigenen öffentlichen IPv4 (Default: `https://ipv4.icanhazip.com`) | – |
| `STATE_DIR` | nein | Verzeichnis für Cache/Lock/Health-Dateien im Container (Default: `/state`) | – |

Eine Vorlage findest du in [`.env.example`](.env.example).

## Health-Check

Der Container startet einen kleinen Webserver auf Port `22222`, der das `/state`-Verzeichnis ausliefert:

- `http://<host>:22222/health.json` – Status als JSON (`status`, `message`, `ip`, `dns_value`, `timestamp_utc`)
- `http://<host>:22222/healthz` – einfacher Text-Status (`OK` / `ERROR`)

## Funktionsweise

1. Eigene öffentliche IPv4 ermitteln
2. Mit zwischengespeicherter letzter IP vergleichen – bei Gleichstand: fertig, kein API-Call
3. Zone-ID und passendes RRset (Name + Typ) über die Hetzner API auflösen
4. Falls der aktuelle DNS-Wert von der eigenen IP abweicht: Record per `set_records` aktualisieren
5. Health-Status nach jedem Lauf schreiben

Das Ganze läuft in einer Schleife mit 5 Minuten Pause zwischen den Durchläufen (`start.sh`).

## Grenzen

- Nur IPv4 / A-Records, kein IPv6/AAAA
- Der Ziel-Record muss vorher existieren – es werden keine neuen Records angelegt

## Lizenz

MIT
