# Silicon Client

A Minecraft: Java Edition client written from scratch in Swift and Metal, for macOS.

Not a launcher, not a mod loader, and not a modified copy of the game. The renderer, world mesher,
resource pipeline and network stack are all original code. It speaks the Minecraft Java protocol
directly and draws the world itself.

**Target version:** Minecraft 26.2 (protocol 776)

---

## Status

In active development, started August 2026. It currently connects to a local server, streams and
renders the world, and lets you fly around it. It is not yet a general-purpose client — there is no
account sign-in, no block interaction and no inventory.

### What works today

- **Protocol** — handshake, login, configuration and play phases; chunk streaming, player position,
  keepalives, chunk batching
- **World decoding** — paletted chunk sections, the full block registry (1,196 blocks, 32,366 states), NBT
- **Rendering** — Metal renderer with a background mesher, face culling driven by the game's own
  block models, correct handling of transparent blocks such as leaves and glass
- **Lighting** — sky and block light read from the server and applied per face
- **Textures** — resolved through the game's model and blockstate files, including animated
  textures with their original frame timings
- **Debug overlay** — fn+F3 shows frame rate, position, chunk, loaded chunks and meshing time

### Planned

Microsoft account sign-in, block breaking and placing, inventory, entities, chat, sound, and a
launcher interface.

---

## Requirements

- macOS 14 or later, Apple Silicon
- A Java runtime, used to run the bundled singleplayer server
- A genuine, paid Minecraft: Java Edition account (once sign-in is implemented)
- An internet connection on first launch

---

## Building

```sh
git clone https://github.com/Nobody-Faliure/silicon-client.git
cd silicon-client
open "Silicon Client.xcodeproj"
```

Then build and run from Xcode.

For anything performance-related, use the Release configuration — Swift's debug builds are several
times slower on the world mesher, and figures taken from a debug build are not meaningful.

---

## How it uses Minecraft's files

Silicon Client contains **no Minecraft code, textures, sounds or other assets**.

On first launch it downloads the official client and server jars from Mojang's own distribution
servers, onto the user's machine, and extracts the textures and model definitions it needs. Nothing
belonging to Mojang is redistributed as part of this project.

The block registry is likewise generated on the user's machine by running Mojang's own server jar
in its data-generator mode, rather than being shipped.

---

## Authentication

Account sign-in is not yet implemented. When it is, it will use **Microsoft's own OAuth sign-in**
(device code flow) — the client will never ask for or handle a password, and will never offer an
offline or unauthenticated mode for connecting to servers.

A valid Minecraft: Java Edition account will be required, exactly as with the official client.

---

## Licence and legal

This project is an independent work. It is not affiliated with, endorsed by, or supported by
Mojang Studios or Microsoft.

It is not sold, and no part of it is monetised. It does not enable playing Minecraft without
owning it, and it provides no capability beyond what the official client offers.

> **NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT.**

Minecraft is a trademark of Mojang Studios.
