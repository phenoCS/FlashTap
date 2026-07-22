export function modifyConfig(config) {
  config.models = [
    {
      title: "Autodetect",
      provider: "ollama",
      model: "AUTODETECT"
    }
  ];
  config.tabAutocompleteModel = {
    title: "Autodetect",
    provider: "ollama",
    model: "AUTODETECT"
  };
  return config;
}