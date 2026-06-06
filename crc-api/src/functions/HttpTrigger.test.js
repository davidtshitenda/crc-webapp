// HttpTrigger.test.js
// Tests for the CRC visitor counter Azure Function
// Run with: npm test

// ── MOCK @azure/cosmos ──────────────────────────────────────────────────────
// We don't want tests hitting the real Cosmos DB — we mock the SDK so tests
// run offline, instantly, and don't consume RUs or alter real data.

const mockReplace = jest.fn();
const mockRead = jest.fn();
const mockItem = jest.fn(() => ({ read: mockRead, replace: mockReplace }));
const mockContainer = jest.fn(() => ({ item: mockItem }));
const mockDatabase = jest.fn(() => ({ container: mockContainer }));

jest.mock('@azure/cosmos', () => ({
  CosmosClient: jest.fn(() => ({
    database: mockDatabase
  }))
}));

// ── MOCK @azure/functions ───────────────────────────────────────────────────
// We capture the handler function that app.http() registers so we can call
// it directly in tests without needing the full Functions runtime.

let registeredHandler;

jest.mock('@azure/functions', () => ({
  app: {
    http: jest.fn((name, config) => {
      registeredHandler = config.handler;
    })
  }
}));

// ── LOAD THE FUNCTION ───────────────────────────────────────────────────────
// Importing the module triggers app.http() which registers the handler above.

require('./HttpTrigger');

// ── HELPERS ─────────────────────────────────────────────────────────────────

function makeRequest() {
  return {};
}

function makeContext() {
  return { log: jest.fn() };
}

// ── TESTS ───────────────────────────────────────────────────────────────────

describe('HttpTrigger — Visitor Counter Function', () => {

  beforeEach(() => {
    // Reset all mocks before each test so they don't bleed into each other
    jest.clearAllMocks();
  });

  // ── TEST 1 ────────────────────────────────────────────────────────────────
  test('returns status 200 on successful request', async () => {
    // Arrange: Cosmos DB returns a counter document with count 5
    mockRead.mockResolvedValue({ resource: { id: 'counter', count: 5 } });
    mockReplace.mockResolvedValue({});

    // Act: call the handler
    const response = await registeredHandler(makeRequest(), makeContext());

    // Assert: HTTP 200
    expect(response.status).toBe(200);
  });

  // ── TEST 2 ────────────────────────────────────────────────────────────────
  test('increments the count by 1 and returns the new value', async () => {
    // Arrange: current count is 10
    mockRead.mockResolvedValue({ resource: { id: 'counter', count: 10 } });
    mockReplace.mockResolvedValue({});

    // Act
    const response = await registeredHandler(makeRequest(), makeContext());
    const body = JSON.parse(response.body);

    // Assert: returned count is 11
    expect(body.count).toBe(11);
  });

  // ── TEST 3 ────────────────────────────────────────────────────────────────
  test('writes the incremented count back to Cosmos DB', async () => {
    // Arrange: current count is 3
    mockRead.mockResolvedValue({ resource: { id: 'counter', count: 3 } });
    mockReplace.mockResolvedValue({});

    // Act
    await registeredHandler(makeRequest(), makeContext());

    // Assert: replace was called with count = 4
    expect(mockReplace).toHaveBeenCalledTimes(1);
    expect(mockReplace).toHaveBeenCalledWith(
      expect.objectContaining({ count: 4 })
    );
  });

  // ── TEST 4 ────────────────────────────────────────────────────────────────
  test('response body is valid JSON containing a count field', async () => {
    // Arrange
    mockRead.mockResolvedValue({ resource: { id: 'counter', count: 7 } });
    mockReplace.mockResolvedValue({});

    // Act
    const response = await registeredHandler(makeRequest(), makeContext());

    // Assert: body parses cleanly and has a count field
    expect(() => JSON.parse(response.body)).not.toThrow();
    expect(JSON.parse(response.body)).toHaveProperty('count');
  });

  // ── TEST 5 ────────────────────────────────────────────────────────────────
  test('response includes correct Content-Type and CORS headers', async () => {
    // Arrange
    mockRead.mockResolvedValue({ resource: { id: 'counter', count: 1 } });
    mockReplace.mockResolvedValue({});

    // Act
    const response = await registeredHandler(makeRequest(), makeContext());

    // Assert: headers required for browser compatibility
    expect(response.headers['Content-Type']).toBe('application/json');
    expect(response.headers['Access-Control-Allow-Origin']).toBe('*');
  });

  // ── TEST 6 ────────────────────────────────────────────────────────────────
  test('reads from the correct Cosmos DB container and item', async () => {
    // Arrange
    mockRead.mockResolvedValue({ resource: { id: 'counter', count: 0 } });
    mockReplace.mockResolvedValue({});

    // Act
    await registeredHandler(makeRequest(), makeContext());

    // Assert: correct database, container, and item were targeted
    expect(mockItem).toHaveBeenCalledWith('counter', 'counter');
  });

  // ── TEST 7 ────────────────────────────────────────────────────────────────
  test('handles Cosmos DB read failure gracefully', async () => {
    // Arrange: simulate Cosmos DB being unavailable
    mockRead.mockRejectedValue(new Error('Cosmos DB connection failed'));

    // Act & Assert: function should throw (not silently fail)
    await expect(
      registeredHandler(makeRequest(), makeContext())
    ).rejects.toThrow('Cosmos DB connection failed');
  });

});