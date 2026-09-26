import { GAME_BUILD } from "@/lib/world-catalog";

export default function Intro() {
  return (
    <section>
      <h1 className="sr-only">DST Seedfinder</h1>
      <p className="lead">
        Don&apos;t Starve Together seed finding tool. Currently supports DST v{GAME_BUILD}. This is mostly a hobby project, no future support is
        guaranteed, nothing is monetized (credits are purely to prevent abuse).
      </p>
      <details className="help">
        <summary>How do I use a seed?</summary>
        <div>
          <ol>
            <li>
              Subscribe to{" "}
              <a href="https://steamcommunity.com/workshop/filedetails/?id=1378549454" target="_blank" rel="noreferrer">
                [API] Gem Core
              </a>{" "}
              on the Steam Workshop.
            </li>
            <li>When creating a world, enable the mod in the &quot;Mods&quot; section.</li>
            <li>Go to &quot;Forest&quot; -&gt; &quot;World Generation&quot; and set it under the world seed.</li>
            <li>
              Do not tweak any other &quot;World Generation&quot; settings that are unsupported, changing any of these settings will result in a
              completely different world.
            </li>
          </ol>
        </div>
      </details>
    </section>
  );
}
