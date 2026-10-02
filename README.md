# dst-seedfinder

[![forthebadge](https://forthebadge.com/badges/contains-technical-debt.svg)]()

A seed finder for Don't Starve Together. Supports forest and cave worlds on version `756039` on Windows and Linux.

This is mostly a toy project, the majority of the code is very sloppy and not production ready.

## Structure

### seedfinder

The real deal. This does all the heavy lifting. It's the majority of the game's world generation code ported to Bend and
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
seedfinder. The script pulls the JSON config from the backend, runs the seedfinder, and pipes all outputs to the
backend.

### bend

We use a custom version of Bend which has WebAssembly support. This is used so users can find seeds in their browser.
This also contains a patch which fixes a Bend bug ([bendlang/bend#1093](https://github.com/bendlang/bend/issues/1093)).

### scripts

This contains a bunch of scripts for building, setting up the build environment and generating other files:

- `catalog` - Generates the prefab catalog for the website using the game scripts.
- `gen` - Generates a lot of data for the seedfinder. A lot of the Bend code is auto generated using these scripts, so
  when the game updates this code should still work (unless Klei changes a lot of stuff in the engine).
- `groundtruth` - Spins up a dedicated DST server with a custom mod to dump world generation data. This was originally
  used to validate to ensure we haven't broken any world generation code, but now it's mostly used to port the tool to
  newer versions.
- `harness` - Contains the Lua harness that lets us run some game scripts without actually running the game.

## Implementation Journey

The majority of this code was generated with AI with a human in the loop. None of this is really amazing code,
but considering the scope of this project and this being a solo project nobody else will probably work on, it's
good enough™.

Most of the process was just grunt work though, here's what the entire process looked like:

1. I made a bunch of scripts to run DST dedicated servers and a mod that dumps world generation data. This was used
   for full validation, so that I could ensure it actually generates proper seeds.
   See [groundtruth](scripts/groundtruth).
2. This also included a Windows in Docker setup using the [dockurr/windows](https://github.com/dockur/windows) image.
3. Bunch of dependencies and tools were downloaded and provided:

- the game scripts
- the source code for the Lua version the game uses (5.1.5)
- [boost](https://www.boost.org/) 1.52.0
- ghidra 12.1.4
- previously mentioned tools to run the game on Linux and Windows

4. The `harness` was made next, which allows for running some game scripts without the game.
5. The set piece algorithm was ported to Bend first and compared against the game. This was mostly to see how well this
   setup works, and it worked very well indeed.
6. Using ghidra the engine methods that are required for world generation were all reverse engineered.
7. These methods where then ported to C++, so at this point I was able to run the entire world generation code without
   the game running. This allowed me to add a lot of debugs and compare the code I port to the game, without having to
   wait a long time for the dedicated server to generate the world.
8. I looked at other seed finding mods to see how their searching worked and what features they had,
   and wrote a search spec.
9. The search spec was implemented in Bend and the biomes and tasks searching was implemented alongside the existing
   set piece code.
10. Now everything could slowly be ported to Bend bit by bit, this part took the longest. The majority of this stuff
    could be done in parallel, so there was a bunch of subagents porting different pieces of the world generation logic
    at the same time.
11. At this point I had a working seedfinder, but it was slow. I spent a bunch of time trying to get a lot of the code
    working on the GPU, but unfortunately I then realized that the GPU is just not great at doing this work (lol).
12. I decided to optimize a lot of the code then, most of the work was spent computing KK layouts, so that
    was ported to [C and optimized](seedfinder/native/kk.c). This was a massive improvement and I could now generate
    worlds pretty quickly. Prefiltering (e.g. checking if we have the right biomes of tasks) was extremely fast and I
    was able to check ~15M worlds per second. Generating worlds was much slower, but I was able to get ~20 worlds per
    second which is still massively faster than the game.

While all of these steps were happening, I was also working on the website and the runner. Originally the idea was to
run the seedfinder on [Runpod](https://www.runpod.io/), but I realized that [Vast.ai](https://vast.ai/) is just much
better for this and swapped to it. Later I also added a custom version of Bend with WebAssembly support, so users can
just run the seedfinder in their browser, which was still surprisingly fast (~80-90% of the speed).

In the end, a lot of the code was cleaned up and improved. During the entire process, the agents were heavily monitored
and steered. Everything was also fully sandboxed to ensure it doesn't fuck up some shit while it's running.
The entire process took ~3 days.  
