terraform {
  cloud {
    organization = "hashi-demos-apj"

    workspaces {
      name = "sandbox_consumer_web_stack"
    }
  }
}
