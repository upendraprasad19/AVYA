import { z } from "https://deno.land/x/zod@v3.23.8/mod.ts";

/** Gemini FunctionDeclaration shape (subset). See https://ai.google.dev/gemini-api/docs/function-calling */
export interface GeminiFunctionDeclaration {
  name: string;
  description: string;
  parameters: GeminiSchema;
}

export interface GeminiSchema {
  type: "STRING" | "NUMBER" | "INTEGER" | "BOOLEAN" | "ARRAY" | "OBJECT";
  description?: string;
  enum?: string[];
  items?: GeminiSchema;
  properties?: Record<string, GeminiSchema>;
  required?: string[];
  nullable?: boolean;
}

/** Convert a Zod schema to a Gemini schema (recursive). Throws on unsupported types. */
export function zodToGeminiSchema(zodType: z.ZodTypeAny): GeminiSchema {
  const def = zodType._def;

  // Handle .describe() metadata
  let description: string | undefined;
  if ("description" in def && typeof def.description === "string") {
    description = def.description;
  }

  // ZodOptional / ZodNullable: unwrap, mark nullable
  if (zodType instanceof z.ZodOptional || zodType instanceof z.ZodNullable) {
    // deno-lint-ignore no-explicit-any
    const inner = zodToGeminiSchema((zodType._def as any).innerType);
    return { ...inner, nullable: true, ...(description ? { description } : {}) };
  }

  // ZodDefault: unwrap
  if (zodType instanceof z.ZodDefault) {
    // deno-lint-ignore no-explicit-any
    return zodToGeminiSchema((zodType._def as any).innerType);
  }

  if (zodType instanceof z.ZodString) {
    return { type: "STRING", ...(description ? { description } : {}) };
  }

  if (zodType instanceof z.ZodNumber) {
    // deno-lint-ignore no-explicit-any
    const isInt = (zodType._def as any).checks?.some((c: any) => c.kind === "int");
    return { type: isInt ? "INTEGER" : "NUMBER", ...(description ? { description } : {}) };
  }

  if (zodType instanceof z.ZodBoolean) {
    return { type: "BOOLEAN", ...(description ? { description } : {}) };
  }

  if (zodType instanceof z.ZodEnum) {
    return {
      type: "STRING",
      // deno-lint-ignore no-explicit-any
      enum: (zodType._def as any).values,
      ...(description ? { description } : {}),
    };
  }

  if (zodType instanceof z.ZodArray) {
    return {
      type: "ARRAY",
      // deno-lint-ignore no-explicit-any
      items: zodToGeminiSchema((zodType._def as any).type),
      ...(description ? { description } : {}),
    };
  }

  if (zodType instanceof z.ZodObject) {
    // deno-lint-ignore no-explicit-any
    const shape = (zodType._def as any).shape();
    const properties: Record<string, GeminiSchema> = {};
    const required: string[] = [];
    for (const [key, value] of Object.entries(shape)) {
      const v = value as z.ZodTypeAny;
      properties[key] = zodToGeminiSchema(v);
      if (!(v instanceof z.ZodOptional) && !(v instanceof z.ZodDefault)) {
        required.push(key);
      }
    }
    return {
      type: "OBJECT",
      properties,
      ...(required.length > 0 ? { required } : {}),
      ...(description ? { description } : {}),
    };
  }

  throw new Error(`zodToGeminiSchema: unsupported Zod type: ${zodType.constructor.name}`);
}

/** Build a complete Gemini FunctionDeclaration from a tool definition. */
export function toolToFunctionDeclaration(tool: {
  name: string;
  description: string;
  selectionHints?: string;
  schema: z.ZodTypeAny;
}): GeminiFunctionDeclaration {
  const params = zodToGeminiSchema(tool.schema);
  // Top-level must be OBJECT
  if (params.type !== "OBJECT") {
    throw new Error(
      `Tool '${tool.name}' schema must be a Zod object at the top level (got ${params.type}).`,
    );
  }
  const fullDescription = tool.selectionHints
    ? `${tool.description}\n\nWHEN TO USE: ${tool.selectionHints}`
    : tool.description;
  return {
    name: tool.name,
    description: fullDescription,
    parameters: params,
  };
}
