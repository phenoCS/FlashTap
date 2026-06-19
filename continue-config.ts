export function modifyConfig(config) {
  config.models = [
    {
      title: "FlashTap-7B",
      provider: "ollama",
      model: "qwen2.5-coder:7b"
    }
  ];
  config.tabAutocompleteModel = {
    title: "FlashTap-7B",
    provider: "ollama",
    model: "qwen2.5-coder:7b"
  };
  return config;
}