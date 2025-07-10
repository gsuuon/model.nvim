import { BufferState } from "./bufferState.ts";

const bufferState = new BufferState();

export function consumeEditEvent(eventData: unknown[]): void {
  // Debug: Log the raw event data
  console.log("Raw event data:", eventData);

  // Parse the event data correctly
  const [_extData, _changeId, startLine, endLine, lines, _more] = eventData as [
    unknown,
    number,
    number,
    number,
    string[],
    boolean,
  ];

  // Debug: Log parsed values
  console.log("Parsed values:", { startLine, endLine, lines });

  // Ensure lines is an array
  const linesArray = Array.isArray(lines) ? lines : [];

  // Debug: Log the lines array
  console.log("Lines array:", linesArray);

  // Apply the edit to the buffer state
  bufferState.applyEdit(startLine, endLine, linesArray);

  // Log the updated state
  bufferState.logState();
}
