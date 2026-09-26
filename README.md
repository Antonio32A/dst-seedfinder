# dst-seedfinder

[![forthebadge](https://forthebadge.com/badges/contains-technical-debt.svg)]()

A seed finder for Don't Starve Together. Supports forest worlds on version `747465` on Windows and Linux.

This is mostly a toy project, the majority of the code is very sloppy and not production ready. 

## Structure

### seedfinder 

The real deal. This does all the heavy lifting. It's the majority of the game's world geneneration code ported to Bend and
optimized to generate worlds as fast as possible. 

It uses [Bend](https://github.com/bendlang/bend) as it's a pretty fast language, and I honestly just wanted to fuck 
around with it. It does not support CUDA/GPU world generation, as when I was testing it, it was unfortunately just
too slow and not the right job for the GPU. It is still, very fast and will take advantage of your entire CPU. 

A tiny amount of the code is also in C, because Bend currently does not support F64 and the majority of the world
generation time is spent computing KK layouts, which are very slow with the boxed F64 this project reimplements.

To use it, you define a JSON config which says what you want to search for (e.g., a world with five walking canes 
and five `MiscBoon` set pieces). You can see the spec for it in [docs/config.md](docs/config.md).

### website

This is a vinext app that lets users sign in and submit seed searches. Users currently sign in with Discord (it was
the simplest solution) and are given a set number of credits. Credits are purely used for rate limiting.

All seed searches are run on a different server, currently this comes from Vast.ai. When you press "Find seeds",
it literally spins up a new server which downloads the runner image, passes the config to it, and then
starts finding seeds on there. 

This runs on Cloudflare Workers, as I was lazy to properly deploy it anywhere else.

### runner

This is the Docker image that Vast.ai pulls and runs on boot. It runs Alpine Linux with a small script which runs the 
seedfinder. The script pulls the JSON config from the backend, runs the seedfinder, and pipes all outputs to the backend.

### bend

We use a custom version of Bend which has WebAssembly support. This is used so users can find seeds in their browser.
This also contains a patch which fixes a Bend bug ([bendlang/bend#1093](https://github.com/bendlang/bend/issues/1093)).

### scripts

This contains a bunch of scripts for building, setting up the build environment and generating other files:
- `catalog` - Generates the prefab catalog for the website using the game scripts.
- `gen` - Generates a lot of data for the seedfinder. A lot of the Bend code is auto generated using these scripts, so
when the game updates this code should still work (unless Klei changes a lot of stuff in the engine). 
- `groundtruth` - Spins up a dedicated DST server with a custom mod to dump world generation data. This was originally used to
validate to ensure we haven't broken any world generation code, but now it's mostly used to port the tool to newer versions.
- `harness` - Contains the Lua harness that lets us run some game scripts without actually running the game.

