import { projectName } from "@/lib/project";

export function App() {
  return (
    <main className="flex min-h-svh items-center justify-center">
      <h1 className="font-semibold text-2xl">{projectName}</h1>
    </main>
  );
}
