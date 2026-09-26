import { GAME_BUILD } from "@/lib/world-catalog";

export default function Intro() {
    return (
            <section>
                <h1 className="sr-only">DST Seedfinder</h1>
                <p className="lead">
                    Don&apos;t Starve Together seed finding tool. Currently supports DST v{GAME_BUILD}.
                    <br/>
                    This is mostly a hobby project, no future support is guaranteed.
                </p>
                <details className="help">
                    <summary>How do I use a seed?</summary>
                    <div>
                        <ol>
                            <li>
                                Subscribe to{" "}
                                <a href="https://steamcommunity.com/workshop/filedetails/?id=1378549454" target="_blank"
                                   rel="noreferrer">
                                    [API] Gem Core
                                </a>{" "}
                                on the Steam Workshop.
                            </li>
                            <li>When creating a world, enable the mod in the &quot;Mods&quot; section.</li>
                            <li>Go to &quot;Forest&quot; -&gt; &quot;World Generation&quot; and set it under the world
                                seed.
                            </li>
                            <li>
                                Do not tweak any other &quot;World Generation&quot; settings that are unsupported,
                                changing any of these settings will result in a
                                completely different world.
                            </li>
                        </ol>
                    </div>
                </details>
                <details className="help">
                    <summary>What are credits?</summary>
                    <div>
                        <p>
                            Credits are purely used for Cloud seed finding. You cannot buy them, but you can ask me on
                            Discord and I might give you some.
                            They&apos;re purely used to prevent people from spending all my money as the Cloud servers
                            are not cheap.
                        </p>
                    </div>
                </details>
                <details className="help">
                    <summary>How is this monetized?</summary>
                    <div>
                        <p>It isn&apos;t.</p>
                    </div>
                </details>
                <details className="help">
                    <summary>Where can I find the source code?</summary>
                    <div>
                        <p>
                            It&apos;s available on{" "}
                            <a href="https://github.com/Antonio32A/dst-seedfinder" target="_blank" rel="noreferrer">
                                GitHub
                            </a>
                            .
                        </p>
                    </div>
                </details>
                <details className="help">
                    <summary>How do I effectively use this?</summary>
                    <div>
                        <p>
                            You should try and balance the fast options (e.g. set pieces) with the slower World details
                            options. This means that if you e.g.
                            want to find a world with 3 Walking Canes, you should select ~5 <code>MiscBoon</code> set
                            pieces, so that the tool skips the
                            majority of the worlds that are unlikely to have 3 Walking Canes.
                        </p>
                    </div>
                </details>
            </section>
    );
}
