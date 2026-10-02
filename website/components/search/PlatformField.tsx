"use client";

import SegmentedControl from "@/components/ui/SegmentedControl";
import { type Platform, PLATFORM_LABELS, PLATFORMS } from "@/lib/config/seedfinder-config";

interface PlatformFieldProps {
    platform: Platform;
    onChange: (platform: Platform) => void;
}

export default function PlatformField({ platform, onChange }: PlatformFieldProps) {
    return (
            <div>
                <SegmentedControl
                        legend="Platform"
                        options={PLATFORMS.map((value) => ({ value, label: PLATFORM_LABELS[value] }))}
                        value={platform}
                        onChange={onChange}
                />
                <p className="hint">The OS of the computer that generates the world.</p>
            </div>
    );
}
