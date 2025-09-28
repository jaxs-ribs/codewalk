export const toolDefinitions = [{
  functionDeclarations: [
    {
      name: "write_artifact",
      description: "Write description or phasing markdown",
      parameters: {
        type: "OBJECT",
        properties: {
          artifact_type: {
            type: "STRING",
            enum: ["description", "phasing"],
            description: "Type of artifact to write"
          },
          content: {
            type: "STRING",
            description: "Full markdown content to write"
          }
        },
        required: ["artifact_type", "content"]
      }
    },
    {
      name: "read_artifact",
      description: "Read description, phasing, or specific phase",
      parameters: {
        type: "OBJECT",
        properties: {
          artifact_type: {
            type: "STRING",
            enum: ["description", "phasing", "phase"],
            description: "Type of artifact to read"
          },
          phase_number: {
            type: "INTEGER",
            description: "Phase number if reading specific phase"
          }
        },
        required: ["artifact_type"]
      }
    },
    {
      name: "route_intent",
      description: "Classify user input as directive or conversation",
      parameters: {
        type: "OBJECT",
        properties: {
          intent: {
            type: "STRING",
            enum: ["directive", "conversation"],
            description: "Classification of user input"
          },
          action: {
            type: "STRING",
            description: "Specific action if directive"
          },
          input_type: {
            type: "STRING",
            enum: ["statement", "yes_no_question", "technical_question", "brainstorming", "unclear"],
            description: "Type of conversational input"
          },
          reasoning: {
            type: "STRING",
            description: "Brief explanation of classification"
          }
        },
        required: ["intent", "reasoning"]
      }
    }
  ]
}];