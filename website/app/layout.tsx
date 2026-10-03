import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import ThemeToggle from "@/components/shell/ThemeToggle";
import { LocalSearchProvider } from "@/lib/browser-search/use-local-search";
import { THEME_INIT_SCRIPT } from "@/lib/client/theme";
import { siteName } from "@/lib/site-metadata";
import "./globals.css";

const DESCRIPTION = "Don't Starve Together seed finding tool";

export async function generateMetadata(): Promise<Metadata> {
    return {
        metadataBase: new URL(`https://${(await headers()).get("host")}`),
        title: "DST Seedfinder",
        description: DESCRIPTION,
        icons: { icon: "/favicon.png" },
        openGraph: {
            type: "website",
            siteName: siteName(),
            title: "DST Seedfinder",
            description: DESCRIPTION,
            images: [{ url: "/favicon.png", width: 50, height: 50 }]
        },
        twitter: { card: "summary" }
    };
}

export const viewport: Viewport = {
    width: "device-width",
    initialScale: 1,
    themeColor: "#fc5821"
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
    return (
            <html lang="en" suppressHydrationWarning>
            <head>
                <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }}/>
            </head>
            <body>
            <div className="container">
                <LocalSearchProvider>{children}</LocalSearchProvider>
                <footer className="footer">
                    <span>© {new Date().getFullYear()} Antonio32A</span>
                    <ThemeToggle/>
                </footer>
            </div>
            </body>
            </html>
    );
}
