"use client";

import { useRouter } from "next/navigation";
import { type FormEvent, useEffect, useState } from "react";
import PlatformField from "@/components/search/PlatformField";
import Brand from "@/components/shell/Brand";
import SegmentedControl from "@/components/ui/SegmentedControl";
import { rememberMapOrigin } from "@/lib/client/map-origin";
import {
    DEFAULT_PLATFORM,
    DEFAULT_SHARD,
    type Platform,
    type Shard,
    SHARD_LABELS,
    SHARDS
} from "@/lib/config/seedfinder-config";
import { pickedMapPath } from "@/lib/world-map/map-route";

export default function MapPicker() {
    const router = useRouter();
    const [platform, setPlatform] = useState<Platform>(DEFAULT_PLATFORM);
    const [shard, setShard] = useState<Shard>(DEFAULT_SHARD);
    const [seed, setSeed] = useState("");
    const [error, setError] = useState("");

    useEffect(() => rememberMapOrigin("/map"), []);

    const open = (event: FormEvent) => {
        event.preventDefault();
        const picked = pickedMapPath(platform, seed, shard);
        if ("error" in picked) setError(picked.error);
        else router.push(picked.path);
    };

    return (
            <>
                <header className="header">
                    <Brand/>
                </header>
                <main className="content">
                    <section>
                        <h1 className="sr-only">DST Seedfinder world map</h1>
                        <p className="lead">
                            View the world map of any seed. Map generation happens in your browser, so it may take a
                            few seconds to load.
                        </p>
                    </section>
                    <form className="section search" aria-labelledby="map-seed" onSubmit={open}>
                        <h2 id="map-seed" className="section-title">
                            Open a map
                        </h2>
                        <div className="search__row">
                            <SegmentedControl
                                    legend="World"
                                    options={SHARDS.map((value) => ({ value, label: SHARD_LABELS[value] }))}
                                    value={shard}
                                    onChange={setShard}
                            />
                            <PlatformField platform={platform} onChange={setPlatform}/>
                        </div>
                        <label className="start-seed">
                            <span className="seg__legend">Seed</span>
                            <input
                                    type="text"
                                    inputMode="numeric"
                                    autoComplete="off"
                                    placeholder="1234567890"
                                    value={seed}
                                    onChange={(event) => {
                                        setSeed(event.target.value);
                                        setError("");
                                    }}
                            />
                        </label>
                        <div className="search__actions">
                            <button type="submit" disabled={seed.trim() === ""}>Map</button>
                        </div>
                        {error && <p className="notice notice--error" role="alert">{error}</p>}
                    </form>
                </main>
            </>
    );
}
