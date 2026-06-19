export function modifyConfig(config) {
  config.models = [
    {
      title: "LocalCoder-7B",
      provider: "ollama",
      model: "qwen2.5-coder:7b"
    }
  ];
  config.tabAutocompleteModel = {
    title: "LocalCoder-7B",
    provider: "ollama",
    model: "qwen2.5-coder:7b"
  };
  return config;
}