export class BufferState {
  private lines: string[];

  constructor(initialLines: string[] = []) {
    this.lines = [...initialLines];
  }

  // Apply edits to the buffer
  applyEdit(startLine: number, endLine: number, newLines: string[]): void {
    // Handle sentinel value for endLine (e.g., -1 means end of buffer)
    const resolvedEndLine = endLine === -1 ? this.lines.length : endLine;

    // Replace lines from startLine to resolvedEndLine (end-exclusive) with newLines
    this.lines.splice(startLine, resolvedEndLine - startLine, ...newLines);
  }

  // Get the current state of the buffer
  getState(): string[] {
    return [...this.lines];
  }

  // Log the current state
  logState(): void {
    console.log("Current buffer state:");
    this.lines.forEach((line, index) => {
      console.log(`${index}: ${line}`);
    });
  }
}
