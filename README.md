# DNASrep (Dockerized)

A ready-to-run **Docker Compose** packaging of **DNASrep**, a DNAS replacement
server for the PlayStation 2. It lets a real PS2 pass DNAS disc authentication by
replaying packets that were captured by the DNAS forever project.

> **This is a fork.** All of the DNAS replay logic, captured packets and game
> support come from **[gh0stl1ne's DNASrep](https://gitlab.com/gh0stl1ne/DNASrep)**
> (originally by the_fog, maintained by no23/gh0stl1ne). The **only** purpose of
> this fork is to package that project as a self-contained, reproducible Docker
> setup — with certificates generated at startup so they never expire. Full credit
> for the actual DNAS work goes upstream (see [Credits](#credits)).

## How it works

The PS2 speaks a legacy TLS dialect — an **SSLv2-format ClientHello**, **TLS 1.0**,
weak ciphers (**RC4-SHA / 3DES**) and a **1024-bit RSA** certificate. No modern
distribution's OpenSSL (1.1.1 / 3.x) can serve that anymore. The legacy layer is
therefore isolated in its own tiny service:

```
   PS2  ──legacy TLS──►  [ tls ]  ──plain HTTP──►  [ web ]
                       stunnel +               Apache 2.4 +
                     OpenSSL 1.0.2             PHP 7.4
                     (built from source)       serves /var/www/dnas
```

- **`tls`** — stunnel built against an OpenSSL 1.0.2 (weak ciphers) compiled from
  source. Terminates the PS2's legacy TLS on port 443, generates the certificate
  chain at startup, and forwards plaintext to `web`. This is the only "legacy" piece.
- **`web`** — Debian bullseye, Apache + PHP 7.4 (kept on a maintained base). PHP
  7.4 links OpenSSL 1.1.1, so the `des-ecb` cipher used by `connect.php` works.

Both containers are tiny (≈ 10 MB + ≈ 3 MB of RAM at rest).

## Quick start (pre-built images)

Images are built by CI and published to the GitHub Container Registry, so a host
only needs `docker-compose.yml` and a `.env` — no clone, no build:

```bash
# on each host: drop docker-compose.yml + .env, then
cp .env.example .env      # set HOST_IP, REGION and DNAS_IMAGE
docker compose pull
docker compose up -d
docker compose logs -f
```

Certificates are **generated at startup** (a forged "VeriSign Class 3" chain,
RSA-1024, ~2048 validity) and stored in `./certs`.

### Building the images yourself

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml build
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d
```

(The `tls` image compiles OpenSSL 1.0.2, so this first build takes a few minutes.)

### Images / CI

A GitHub Actions workflow (`.github/workflows/docker.yml`) builds both services
and pushes them to GHCR:

- `${DNAS_IMAGE}/web:latest`
- `${DNAS_IMAGE}/tls:latest`

`DNAS_IMAGE` defaults to `ghcr.io/<owner>/dnasrep` — set it in `.env` to match your
repository path. Packages on GHCR are private by default; make them public (or log
in with `docker login ghcr.io`) so the hosts can pull them.

### Without compose (docker run)

For hosts without the compose plugin (e.g. GCP Container-Optimized OS), use the
`run.sh` helper — it creates the network + volume and runs both containers:

```bash
bash run.sh us        # region = eu (default) | us | jp   (sudo bash run.sh us if docker needs root)
```

On Container-Optimized OS, `/home` is mounted `noexec`, so run it as `bash run.sh`
(not `./run.sh`) and don't bother installing the compose binary — it can't execute
there. Equivalent manual commands:

```bash
docker network create dnas
docker volume create dnas-certs
docker run -d --name dnas-web --network dnas --restart unless-stopped \
  --memory 128m ghcr.io/a-blondel/dnasrep/web:latest
docker run -d --name dnas-tls --network dnas --restart unless-stopped \
  --memory 64m -p 443:443 -e REGION=eu -e BACKEND=web:80 \
  -v dnas-certs:/etc/dnas ghcr.io/a-blondel/dnasrep/tls:latest
```

## One region per deployment

The PS2 **does not send SNI** and **validates the certificate CN** against the
hostname it connects to. A single IP:443 can only present one certificate, so
**each deployment serves exactly one region**. To serve several regions, run one
deployment per region, each on its own IP, and point that region's hostname at it.

Set the region in `.env`:

```ini
REGION=eu        # eu (default), us or jp
```

## DNS configuration (on your own DNS server)

Point the region's DNAS hostname to this host's IP (`HOST_IP`), then set the PS2's
DNS to your DNS server:

```
gate1.eu.dnas.playstation.org  ->  <HOST_IP>     # or gate1.us / gate1.jp
```

## Environment variables (`.env`)

| Variable      | Default   | Purpose |
|---------------|-----------|---------|
| `HOST_IP`     | `0.0.0.0` | Host IP to publish 443 on |
| `REGION`      | `eu`      | Region served: `eu`, `us` or `jp` |
| `REGEN_CERTS` | `true`    | `true` (if missing) / `force` (every start) / `false` (use mounted certs) |

## Certificates

The generator reproduces the structure the PS2 accepts: a forged
`VeriSign Class 3 Public Primary Certification Authority` CA and a leaf whose CN is
`gate1.<region>.dnas.playstation.org`, RSA-1024. The PS2 **does not verify the CA
signature** — it only checks the certificate DN and the validity dates — so a fresh
self-signed CA with the right DN works. Validity is set ~20 years out, avoiding the
original certificate's expiry (the upstream cert was valid only 2016-04-18 →
2026-04-16, after which the PS2 returns `DNAS -610`).

To use pre-existing certificates instead, drop `ca-cert.pem`,
`cert-<region>.pem` and `cert-<region>-key.pem` into `./certs` and set
`REGEN_CERTS=false`.

## Verification

```bash
# Inspect the generated certificate
docker exec dnas-tls /opt/openssl/bin/openssl x509 -in /etc/dnas/cert-eu.pem \
  -noout -subject -issuer -dates

# Legacy handshake from a host with an OpenSSL that still has the weak ciphers
openssl s_client -connect <HOST_IP>:443 -tls1 -cipher 'RC4-SHA'

# Real test: point the PS2 at your DNS, run a supported game's DNAS check, watch logs
docker compose logs -f
```

## Supported games

PS2 DNAS-net disc-based authentication is supported for the regions marked below,
as long as the packets were captured by the DNAS forever project. (Nobunaga's
Ambition Online captures are uncertain, hence the brackets.) This list comes from
the upstream project.

| Game | EU | JP | US |
| ---- | -- | -- | -- |
| 187 Ride Or Die | X |  |  |
| ATV Offroad Fury 3 |  |  | X |
| ATV Offroad Fury 4 |  |  | X |
| AllStar Baseball 2005 |  |  | X |
| Area 51 | X |  |  |
| Battlefield 2 Modern Combat | X | X | X |
| Burnout 3 Takedown | X |  | X |
| Burnout Revenge | X |  | X |
| Call of Duty 2 Big Red One | X |  | X |
| Call of Duty 3 | X |  | X |
| Call of Duty Finest Hour | X |  | X |
| Champions Return to Arms |  |  | X |
| Champions of Norrath |  |  | X |
| Cold Winter |  |  | X |
| Commandos Strike Force |  |  | X |
| Culdcept II |  | X |  |
| Deer Hunter |  |  | X |
| Destruction Derby Arenas |  |  | X |
| Everquest Online Adventures | X |  |  |
| FIFA07 | X |  |  |
| FlatOut 2 |  |  | X |
| Gauntlet Seven Sorrows |  |  | X |
| Greg Hastings Tournament Paintball MAXD |  |  | X |
| Gundam vs ZGundam |  | X |  |
| Hardware Online Arena | X |  |  |
| Hot Wheels Stunt Track Challenge |  |  | X |
| JAK X Combat Racing |  |  | X |
| Jak X | X |  |  |
| KILLZONE | X |  | X |
| KOF MAXIMUM IMPACT REGULATION A |  | X |  |
| KOF Maximum Impact 2 |  | X |  |
| Lemmings | X |  |  |
| MADDEN NFL 07 |  |  | X |
| MLB 06 The Show |  |  | X |
| Madden NFL 2004 |  |  | X |
| Medal of Honor Rising Sun |  |  | X |
| Medal of Honor Soleil levant | X |  |  |
| Metal Gear Solid 3 Snake Eater | X |  |  |
| Metal Gear Solid 3 Disc 2 Persistence | X |  |  |
| Midnight Club 3 DUB Edition Remix |  |  | X |
| Mobile Suit Z Gundam AEUG vs Titans |  | X |  |
| Monster Hunter | X | X | X |
| Monster Hunter G |  | X |  |
| Monster Hunter dos |  | X |  |
| Mortal Kombat Armageddon |  |  | X |
| NASCAR 07 |  |  | X |
| NASCAR Thunder 2004 |  |  | X |
| NBA Ballers |  |  | X |
| NBA Ballers Phenom |  |  | X |
| NFL Street 2 |  |  | X |
| NHL 2K6 | X |  |  |
| Need for Speed Underground | X |  | X |
| Need for Speed Underground 2 | X |  | X |
| NeoGeo Battle Coliseum |  | X |  |
| Network Adaptor StartUp Disc V2 |  |  | X |
| Network Adaptor StartUp Disc V25 |  |  | X |
| Network Start Up Disc v4 |  |  | X |
| (Nobunagas Ambition Online Installation) |  | X |  |
| (Nobunagas Ambition Online installed) |  | X |  |
| PES6 SLES54203 | X |  |  |
| Phantasy Star Universe | X | X | X |
| Phantasy Star Universe Ambition of the Illuminus | X | X | X |
| Phantasy Star Universe Premiere Disc |  | X |  |
| PlayStation BB Navigator 032 |  | X |  |
| Pro Evolution Soccer 6 SLES 54360 | X |  |  |
| Project Snowblind | X |  |  |
| Ratchet Clank Up Your Arsenal |  |  | X |
| Ratchet Deadlocked |  |  | X |
| Resident Evil Outbreak File 1 |  | X | X |
| Resident Evil Outbreak File 2 | X | X | X |
| Risk Global Domination |  |  | X |
| Robotech Invasion |  |  | X |
| Rogue Trooper |  |  | X |
| SAMURAI SHODOWN VI |  | X |  |
| Sniper Elite |  |  | X |
| Socom II US NAVY SEALs | X |  | X |
| Socom III US NAVY SEALs | X |  | X |
| Socom US NAVY SEALs | X |  |  |
| Socom US NAVY SEALs Combined Assault | X |  | X |
| Splinter Cell Double agent | X |  |  |
| Splinter Cell Pandora Tomorrow | X |  |  |
| Stacked with Daniel Negreanu |  |  | X |
| Star Wars Battlefront | X | X | X |
| Star Wars Battlefront II | X | X | X |
| Syphon Filter The Omega Strain | X |  | X |
| Test Drive Unlimited | X |  |  |
| The King of Fighters Neowave |  | X |  |
| The King of Fighters XI |  | X |  |
| The Sims Busting Out |  |  | X |
| TimeSplitters Future Perfect | X |  | X |
| ToCA Race Driver 3 |  |  | X |
| Tom Clancys Ghost Recon Advance Warfighter | X |  |  |
| Tony Hawks American Wasteland |  |  | X |
| Tony Hawks Underground |  |  | X |
| Tony Hawks Underground 2 |  |  | X |
| Urban Chaos Riot Response |  |  | X |
| WRC Avec Sebastien Loeb Edition 2005 | X |  |  |
| WRC Rally Evolved | X |  |  |
| Warhammer 40000 Fire Warrior | X |  |  |
| Winning Eleven 9 |  | X |  |
| X Men Legends II Rise of Apocalypse |  |  | X |
| XIII |  |  | X |
| hack fragment |  | X |  |

### PS2BBN preservation of update files

Support for the authored DNAS update files and XML files that make BBN work is
included for preservation purposes. Many of the linked destinations no longer
exist. Note: you need a legitimate copy of the install disc and/or a PS2 HDD with
an activated BBN installation.

## Credits

This project only dockerizes the work of others. The DNAS replacement itself,
the captured packets and the game support are from:

- **[gh0stl1ne / DNASrep](https://gitlab.com/gh0stl1ne/DNASrep)** — upstream project (the_fog, no23/gh0stl1ne).

### Participants of the original DNAS forever project
FuryK96, Viscosity, DARKFORCE, ResistantFTW, mecha, Hunk91, shade, Richi902,
Anomaladox, DonkeyKong, Gandi.

### PSBBN enhancements
Based-Skid.

And anyone else involved with the project not otherwise mentioned.

## License

Inherited from the upstream project: **GNU AGPL-3.0** (see `LICENSE`).

## Disclaimer

The PS2 console and the DNAS/PS2BBN software were created by Sony Computer
Entertainment. This project is not affiliated with Sony.

DNASrep is meant for use with authentic and licensed PlayStation 2 hardware and
software. It should not be used to facilitate copyright infringement. The
developers and authors of this software cannot be held liable for your use or
misuse of it.
