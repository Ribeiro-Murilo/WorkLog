import { describe, expect, it } from "vitest";

import type { Project, SessionInput } from "../src/shared/types";
import {
  ensureNoDuplicateProject,
  validateProjectFields,
  validateSessionFields,
  ValidationError
} from "../src/shared/validation";

const project: Project = {
  id: "project-1",
  name: "WorkLog",
  client: "Ribeiro Workes",
  dailyRate: 800,
  category: "work",
  tags: [],
  descriptionText: "",
  status: "active",
  isArchived: false,
  isFavorite: false,
  createdAt: "2026-01-01T09:00:00.000Z",
  updatedAt: "2026-01-01T09:00:00.000Z"
};

const sessionInput: SessionInput = {
  projectId: "project-1",
  startTime: "2026-01-01T09:00:00.000Z",
  endTime: "2026-01-01T10:00:00.000Z",
  note: ""
};

describe("validateProjectFields", () => {
  it("accepts filled project fields and zero daily rate", () => {
    expect(() =>
      validateProjectFields({
        name: "  WorkLog  ",
        client: "  Ribeiro Workes  ",
        dailyRate: 0
      })
    ).not.toThrow();
  });

  it("rejects an empty project name", () => {
    expect(() => validateProjectFields({ name: "   ", client: "Client", dailyRate: 100 })).toThrow(
      ValidationError
    );
    expect(() => validateProjectFields({ name: "   ", client: "Client", dailyRate: 100 })).toThrow(
      "O nome do projeto não pode estar vazio."
    );
  });

  it("rejects an empty client", () => {
    expect(() => validateProjectFields({ name: "Project", client: "   ", dailyRate: 100 })).toThrow(
      ValidationError
    );
    expect(() => validateProjectFields({ name: "Project", client: "   ", dailyRate: 100 })).toThrow(
      "O cliente não pode estar vazio."
    );
  });

  it("rejects a negative daily rate", () => {
    expect(() => validateProjectFields({ name: "Project", client: "Client", dailyRate: -1 })).toThrow(
      ValidationError
    );
    expect(() => validateProjectFields({ name: "Project", client: "Client", dailyRate: -1 })).toThrow(
      "O valor por dia não pode ser negativo."
    );
  });
});

describe("validateSessionFields", () => {
  it("accepts a selected project and an end time after the start time", () => {
    expect(() => validateSessionFields(project, sessionInput)).not.toThrow();
  });

  it("rejects a missing project", () => {
    expect(() => validateSessionFields(null, sessionInput)).toThrow(ValidationError);
    expect(() => validateSessionFields(undefined, sessionInput)).toThrow("Selecione um projeto para a sessão.");
  });

  it("rejects an end time equal to the start time", () => {
    expect(() =>
      validateSessionFields(project, {
        ...sessionInput,
        endTime: sessionInput.startTime
      })
    ).toThrow("A hora final deve ser posterior à hora inicial.");
  });

  it("rejects an end time before the start time", () => {
    expect(() =>
      validateSessionFields(project, {
        ...sessionInput,
        endTime: "2026-01-01T08:59:59.000Z"
      })
    ).toThrow(ValidationError);
  });
});

describe("ensureNoDuplicateProject", () => {
  it("accepts no matches", () => {
    expect(() => ensureNoDuplicateProject([])).not.toThrow();
  });

  it("accepts a match with the excluded project id", () => {
    expect(() => ensureNoDuplicateProject([project], "project-1")).not.toThrow();
  });

  it("rejects a match with another project id", () => {
    expect(() => ensureNoDuplicateProject([{ ...project, id: "project-2" }], "project-1")).toThrow(
      ValidationError
    );
    expect(() => ensureNoDuplicateProject([{ ...project, id: "project-2" }], "project-1")).toThrow(
      "Já existe um projeto com esse nome para esse cliente."
    );
  });
});
