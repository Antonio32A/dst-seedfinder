import Link from "next/link";

export default function Brand() {
    return (
            <div className="brand">
                <a href="https://antonio32a.com" className="logo">
                    antonio32a.com
                </a>
                <Link href="/" className="brand__site">
                    seedfinder
                </Link>
            </div>
    );
}
