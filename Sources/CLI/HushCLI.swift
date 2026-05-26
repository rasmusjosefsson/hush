import ArgumentParser

@main
struct CLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hush-cli",
        abstract: "Hush CLI — transcription, history, and model management.",
        version: "0.1.0",
        subcommands: [
            TranscribeCommand.self,
            HistoryCommand.self,
            HealthCommand.self,
            ModelsCommand.self,
            FlowCommand.self,
        ],
        defaultSubcommand: nil
    )
}
