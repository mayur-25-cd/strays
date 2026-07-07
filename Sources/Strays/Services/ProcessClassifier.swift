import Foundation

/// Infers a friendly category + framework fingerprint from a process's short
/// command name and (when available) its full launch command line.
enum ProcessClassifier {

    static func classify(command: String, fullCommand: String?) -> (ProcessCategory, DetectedFramework?) {
        let cmd = command.lowercased()
        let full = (fullCommand ?? command).lowercased()

        // --- Databases (check before generic, they're unambiguous) ---
        if let fw = database(cmd: cmd, full: full) {
            return (.database, fw)
        }

        // --- Docker / containers ---
        if cmd.contains("docker") || full.contains("docker") || cmd.contains("containerd") || cmd == "com.docker.backend" {
            return (.docker, DetectedFramework(name: "Docker", symbol: "shippingbox.fill"))
        }

        // --- AI coding tools / IDEs (relabel so they read as AI, not "editor") ---
        if let fw = aiTool(cmd: cmd, full: full) {
            return (.aiTool, fw)
        }

        // --- JS / TS dev servers (framework detected from the command line) ---
        if let fw = jsFramework(full: full) {
            return (.devServer, fw)
        }

        // --- Python dev servers ---
        if let fw = pythonFramework(full: full) {
            return (.devServer, fw)
        }

        // --- Other language dev servers ---
        if let fw = otherDevServer(cmd: cmd, full: full) {
            return (.devServer, fw)
        }

        // --- Generic JS runtimes with no clear framework ---
        for runtime in ["node", "bun", "deno", "npm", "pnpm", "yarn", "npx"] {
            if cmd == runtime || cmd.hasPrefix(runtime) {
                return (.devServer, DetectedFramework(name: runtime == "node" ? "Node.js" : runtime.capitalized, symbol: "server.rack"))
            }
        }

        // --- Editors / IDEs / language servers ---
        if let fw = editor(cmd: cmd, full: full) {
            return (.editor, fw)
        }

        // --- Apple / system daemons ---
        if isSystem(cmd: cmd) {
            return (.system, DetectedFramework(name: "System", symbol: "gearshape.fill"))
        }

        return (.other, nil)
    }

    // MARK: - Rule groups

    private static func database(cmd: String, full: String) -> DetectedFramework? {
        let map: [(needle: String, name: String, symbol: String)] = [
            ("postgres", "PostgreSQL", "cylinder.split.1x2.fill"),
            ("postmaster", "PostgreSQL", "cylinder.split.1x2.fill"),
            ("mysqld", "MySQL", "cylinder.split.1x2.fill"),
            ("mariadb", "MariaDB", "cylinder.split.1x2.fill"),
            ("mongod", "MongoDB", "leaf.fill"),
            ("redis-server", "Redis", "bolt.horizontal.fill"),
            ("redis", "Redis", "bolt.horizontal.fill"),
            ("memcached", "Memcached", "memorychip.fill"),
            ("clickhouse", "ClickHouse", "cylinder.split.1x2.fill"),
            ("cockroach", "CockroachDB", "cylinder.split.1x2.fill"),
            ("elasticsearch", "Elasticsearch", "magnifyingglass.circle.fill"),
        ]
        for entry in map where cmd.contains(entry.needle) || full.contains(entry.needle) {
            return DetectedFramework(name: entry.name, symbol: entry.symbol)
        }
        return nil
    }

    private static func jsFramework(full: String) -> DetectedFramework? {
        let map: [(needle: String, name: String, symbol: String)] = [
            ("vite", "Vite", "bolt.fill"),
            ("next dev", "Next.js", "triangle.fill"),
            ("next-server", "Next.js", "triangle.fill"),
            ("/next/", "Next.js", "triangle.fill"),
            ("nuxt", "Nuxt", "triangle.fill"),
            ("astro", "Astro", "sparkles"),
            ("remix", "Remix", "music.note"),
            ("gatsby", "Gatsby", "sparkles"),
            ("webpack", "webpack", "shippingbox.fill"),
            ("react-scripts", "Create React App", "atom"),
            ("ng serve", "Angular", "a.circle.fill"),
            ("vue-cli-service", "Vue CLI", "v.circle.fill"),
            ("parcel", "Parcel", "shippingbox.fill"),
            ("storybook", "Storybook", "book.fill"),
            ("expo", "Expo", "iphone"),
            ("turbopack", "Turbopack", "bolt.fill"),
            ("esbuild", "esbuild", "bolt.fill"),
        ]
        for entry in map where full.contains(entry.needle) {
            return DetectedFramework(name: entry.name, symbol: entry.symbol)
        }
        return nil
    }

    private static func pythonFramework(full: String) -> DetectedFramework? {
        let map: [(needle: String, name: String, symbol: String)] = [
            ("uvicorn", "Uvicorn", "server.rack"),
            ("gunicorn", "Gunicorn", "server.rack"),
            ("hypercorn", "Hypercorn", "server.rack"),
            ("fastapi", "FastAPI", "bolt.horizontal.fill"),
            ("flask", "Flask", "flask.fill"),
            ("manage.py runserver", "Django", "d.circle.fill"),
            ("django", "Django", "d.circle.fill"),
            ("streamlit", "Streamlit", "chart.bar.fill"),
            ("http.server", "Python http.server", "server.rack"),
            ("jupyter", "Jupyter", "book.closed.fill"),
        ]
        for entry in map where full.contains(entry.needle) {
            return DetectedFramework(name: entry.name, symbol: entry.symbol)
        }
        return nil
    }

    private static func otherDevServer(cmd: String, full: String) -> DetectedFramework? {
        let map: [(needle: String, name: String, symbol: String)] = [
            ("puma", "Puma (Rails)", "diamond.fill"),
            ("rails", "Rails", "diamond.fill"),
            ("rackup", "Rack", "diamond.fill"),
            ("php -s", "PHP", "p.circle.fill"),
            ("artisan serve", "Laravel", "p.circle.fill"),
            ("dotnet", ".NET", "n.circle.fill"),
            ("hugo", "Hugo", "h.circle.fill"),
            ("jekyll", "Jekyll", "j.circle.fill"),
        ]
        for entry in map where full.contains(entry.needle) {
            return DetectedFramework(name: entry.name, symbol: entry.symbol)
        }
        if cmd == "caddy" { return DetectedFramework(name: "Caddy", symbol: "server.rack") }
        if cmd == "nginx" { return DetectedFramework(name: "nginx", symbol: "server.rack") }
        return nil
    }

    private static func aiTool(cmd: String, full: String) -> DetectedFramework? {
        let map: [(needle: String, name: String, symbol: String)] = [
            ("antigravity", "Gemini Antigravity", "circle.hexagongrid.fill"),
            ("windsurf", "Windsurf", "wind"),
            ("cursor", "Cursor", "cursorarrow.rays"),
            ("codex", "Codex", "curlybraces"),
        ]
        for entry in map where cmd.contains(entry.needle) || full.contains(entry.needle) {
            return DetectedFramework(name: entry.name, symbol: entry.symbol)
        }
        return nil
    }

    private static func editor(cmd: String, full: String) -> DetectedFramework? {
        let map: [(needle: String, name: String, symbol: String)] = [
            ("code helper", "VS Code", "chevron.left.forwardslash.chevron.right"),
            ("code\\x20h", "VS Code", "chevron.left.forwardslash.chevron.right"),
            ("cursor", "Cursor", "chevron.left.forwardslash.chevron.right"),
            ("antigrav", "Antigravity", "chevron.left.forwardslash.chevron.right"),
            ("language_server", "Language Server", "text.and.command.macwindow"),
            ("jetbrains", "JetBrains", "hammer.fill"),
            ("idea", "IntelliJ", "hammer.fill"),
            ("pycharm", "PyCharm", "hammer.fill"),
            ("webstorm", "WebStorm", "hammer.fill"),
            ("sublime", "Sublime Text", "text.cursor"),
        ]
        for entry in map where cmd.contains(entry.needle) || full.contains(entry.needle) {
            return DetectedFramework(name: entry.name, symbol: entry.symbol)
        }
        return nil
    }

    private static func isSystem(cmd: String) -> Bool {
        let systemDaemons = [
            "rapportd", "controlce", "controlcenter", "sharingd", "airplay",
            "launchd", "mdnsresponder", "identityservices", "remoted", "apsd",
            "cloudd", "nsurlsessiond", "trustd", "coreauthd", "wifip2ppd",
            "sockettap", "netbiosd", "bootpd", "screensharingd", "sshd",
        ]
        return systemDaemons.contains { cmd.contains($0) }
    }
}
