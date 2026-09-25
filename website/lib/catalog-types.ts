export type TaskKind = "required" | "optional" | "moon";

export interface TaskInfo {
  id: string;
  name: string;
  kind: TaskKind;
  description: string;
}

export type SwapCategory = "grass" | "twigs" | "berries";

export interface SwapOption {
  id: string;
  name: string;
  description: string;
}

export interface SwapInfo {
  id: SwapCategory;
  name: string;
  description: string;
  options: [SwapOption, SwapOption];
}

export type SetPieceKind = "boon" | "trap" | "poi" | "protected" | "fixed" | "random";

export interface SetPieceInfo {
  id: string;
  name: string;
  kind: SetPieceKind;
  description: string;
  contents: string[];
  rare: boolean;
  maxCount: number;
  fixedCount?: number;
  alwaysPlaced?: boolean;
  candidateTasks?: string[];
}

export interface SetPieceKindInfo {
  id: SetPieceKind;
  name: string;
  description: string;
}
