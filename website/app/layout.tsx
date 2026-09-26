import type { Metadata, Viewport } from "next";
import ThemeToggle from "@/components/ThemeToggle";
import { THEME_INIT_SCRIPT } from "@/lib/theme";
import "./globals.css";

export const metadata: Metadata = {
    title: "DST Seedfinder",
    description: "Find Don't Starve Together world seeds with the biomes, resources and set pieces you want.",
    icons: { icon: "/favicon.png" }
};

export const viewport: Viewport = {
    width: "device-width",
    initialScale: 1
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
    return (
            <html lang="en" suppressHydrationWarning>
            <head>
                <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }}/>
            </head>
            <body>
            <div className="container">
                {children}
                <footer className="footer">
                    <span>© {new Date().getFullYear()} Antonio32A</span>
                    <ThemeToggle/>
                </footer>
            </div>
            </body>
            </html>
    );
}
