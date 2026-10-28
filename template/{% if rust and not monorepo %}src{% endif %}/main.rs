//! Точка входа приложения.

use tracing_subscriber::EnvFilter;

fn main() {
    // Уровень журнала — из `RUST_LOG`, по умолчанию `info`.
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    tracing_subscriber::fmt().with_env_filter(filter).init();

    tracing::info!("{}", greeting());
}

/// Строка о запуске: имя пакета и версия.
fn greeting() -> String {
    format!(
        "{} {} запущен",
        env!("CARGO_PKG_NAME"),
        env!("CARGO_PKG_VERSION")
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greeting_names_package_and_version() {
        let text = greeting();
        assert!(text.starts_with(env!("CARGO_PKG_NAME")));
        assert!(text.contains(env!("CARGO_PKG_VERSION")));
    }
}
