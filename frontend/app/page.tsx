import Link from "next/link";

export default function Home() {
  return (
    <main className="min-h-screen bg-void-950 text-white flex items-center justify-center">
      <div className="text-center space-y-4">
        <p className="text-sm uppercase tracking-[0.3em] text-neon-400">Zero Echelon</p>
        <h1 className="text-3xl font-display">Outpost Frontend</h1>
        <Link
          href="/outpost"
          className="inline-flex items-center justify-center rounded-full border border-neon-500 px-6 py-3 text-sm font-semibold text-neon-400 hover:bg-neon-500/10"
        >
          Enter Outpost
        </Link>
      </div>
    </main>
  );
}
