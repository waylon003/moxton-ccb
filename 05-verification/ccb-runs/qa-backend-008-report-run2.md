[ROUTE]
from: backend-qa
to: team-lead
type: review
task: BACKEND-008
body:

## Request ID
- CCB_REQ_ID: $req

## Acceptance Checklist
- [x] All admin user endpoints use /auth/admin/users: PASS — Runtime verification covered all endpoints under this prefix.
- [x] All endpoints protected by auth + admin: PASS — no token => 401, non-admin token => 403, admin token => 200.
- [x] GET /auth/admin/users supports pagination + keyword + status/role filters: PASS — verified with pageNum/pageSize/keyword/status/role query.
- [x] PUT /auth/admin/users/:id/role switches role correctly: PASS — user -> admin -> user succeeded.
- [x] Self-protection logic works: PASS — self status change/role change/delete all return 403.
- [x] Old /users route removed: PASS — GET /users returned 404.

## Test Matrix
| Endpoint | Scenario | Expected | Actual | Result |
|---|---|---|---|---|
| GET /auth/admin/users | No token | 401 | 401 No token provided | PASS |
| GET /auth/admin/users | Non-admin token | 403 | 403 Administrator privileges required | PASS |
| GET /auth/admin/users | Admin basic pagination | 200 | 200 with list/pageNum/pageSize/total | PASS |
| GET /auth/admin/users | keyword+status+role filter | 200 | 200 filtered list | PASS |
| GET /auth/admin/users/:id | Existing user | 200 | 200 user detail | PASS |
| GET /auth/admin/users/:id | Missing user | 404 | 404 User not found | PASS |
| PUT /auth/admin/users/:id/status | Invalid body status=2 | 400 | 400 Validation Error | PASS |
| PUT /auth/admin/users/:id/status | Self status change | 403 | 403 Cannot change your own status | PASS |
| PUT /auth/admin/users/:id/status | Update another user status | 200 | 200 disable and 200 enable | PASS |
| PUT /auth/admin/users/:id/role | Invalid role | 400 | 400 Validation Error | PASS |
| PUT /auth/admin/users/:id/role | Self role change | 403 | 403 Cannot change your own role | PASS |
| PUT /auth/admin/users/:id/role | Update another user role | 200 | 200 admin and 200 revert user | PASS |
| DELETE /auth/admin/users/:id | Self delete | 403 | 403 Cannot delete your own account | PASS |
| DELETE /auth/admin/users/:id | Delete disposable user | 200 | 200 User deleted successfully | PASS |
| GET /users | Legacy route check | 404 | 404 API endpoint not found | PASS |

## Contract Validation (against E:\moxton-ccb\02-api\auth.md)
- Response envelope is consistent: { code, message, data, timestamp, success }.
- Admin authorization behavior matches docs (401/403/200 paths).
- Endpoint set matches docs: list/detail/status/role/delete.
- Query params used in API docs (pageNum, pageSize, keyword, status, ole) work as expected.

## Baseline Check
| Command | Result | Classification |
|---|---|---|
| 
ode -e "const {spawnSync}=require('node:child_process');const r=spawnSync(process.execPath,['-v']);console.log(r.error?.code||'OK')" | OK | pass |
| 
pm run build | Failed with many TypeScript compile errors | regression |
| 
pm run test:api | Passed (1 file, 2 tests) | pass |

## Failure Details
- Command: 
pm run build
- Classification: egression
- Expected: compile succeeds.
- Actual: large cross-module TypeScript errors (e.g. Cart/Order/Role/routes/services).

## Downstream Impact
- Admin user management API behavior is valid at runtime.
- CI/release pipeline remains blocked by baseline compile failure.

## Final Decision: FAIL
- Acceptance behaviors pass, but mandatory baseline build fails with egression.

## Evidence: Full Command Outputs

### 1) Environment Precheck
Command:
`ash
node -e "const {spawnSync}=require('node:child_process');const r=spawnSync(process.execPath,['-v']);console.log(r.error?.code||'OK')"
`
Output:
`	ext
OK

`

### 2) Baseline Build
Command:
`ash
npm run build
`
Output:
`	ext

> moxton-lotapi@1.0.0 build
> tsc

src/controllers/Cart.ts(120,13): error TS2339: Property 'itemIds' does not exist on type 'unknown'.
src/controllers/Cart.ts(120,22): error TS2339: Property 'selected' does not exist on type 'unknown'.
src/controllers/Cart.ts(163,13): error TS2339: Property 'itemIds' does not exist on type 'unknown'.
src/controllers/Cart.ts(186,9): error TS2554: Expected 0-1 arguments, but got 2.
src/controllers/Cart.ts(230,9): error TS2554: Expected 0-1 arguments, but got 2.
src/controllers/Category.ts(66,7): error TS2561: Object literal may only specify known properties, but 'parentId' does not exist in type 'CategoryCreateInput'. Did you mean to write 'parent'?
src/controllers/Category.ts(104,46): error TS2341: Property 'getAllChildren' is private and only accessible within class 'CategoryModel'.
src/controllers/index.ts(7,56): error TS2307: Cannot find module './Customer' or its corresponding type declarations.
src/controllers/Notification.ts(10,13): error TS6133: 'pageNum' is declared but its value is never read.
src/controllers/Notification.ts(10,26): error TS6133: 'pageSize' is declared but its value is never read.
src/controllers/Notification.ts(13,22): error TS2304: Cannot find name 'page'.
src/controllers/Notification.ts(14,23): error TS2304: Cannot find name 'limit'.
src/controllers/Notification.ts(196,11): error TS6133: 'count' is declared but its value is never read.
src/controllers/OfflineOrder.ts(5,1): error TS6133: 'adminMiddleware' is declared but its value is never read.
src/controllers/OfflineOrder.ts(62,9): error TS2322: Type 'string | null' is not assignable to type 'string | undefined'.
  Type 'null' is not assignable to type 'string | undefined'.
src/controllers/OfflineOrder.ts(63,9): error TS2322: Type 'string | null' is not assignable to type 'string | undefined'.
  Type 'null' is not assignable to type 'string | undefined'.
src/controllers/OfflineOrder.ts(549,7): error TS6133: 'sortBy' is declared but its value is never read.
src/controllers/OfflineOrder.ts(550,7): error TS6133: 'sortOrder' is declared but its value is never read.
src/controllers/Order.ts(22,13): error TS6133: 'pageNum' is declared but its value is never read.
src/controllers/Order.ts(22,26): error TS6133: 'pageSize' is declared but its value is never read.
src/controllers/Order.ts(30,22): error TS2304: Cannot find name 'page'.
src/controllers/Order.ts(31,23): error TS2304: Cannot find name 'limit'.
src/controllers/Order.ts(176,7): error TS2345: Argument of type 'string | null' is not assignable to parameter of type 'string | undefined'.
  Type 'null' is not assignable to type 'string | undefined'.
src/controllers/Order.ts(260,21): error TS2339: Property 'price' does not exist on type '{ product: { id: string; name: string; status: number; metadata: string | null; createdAt: Date; updatedAt: Date; description: string | null; content: string | null; price: Decimal | null; ... 8 more ...; lastStockUpdateAt: Date | null; }; } & { ...; }'.
src/controllers/Order.ts(292,25): error TS2365: Operator '<=' cannot be applied to types 'Decimal' and 'number'.
src/controllers/Order.ts(319,16): error TS18046: 'error' is of type 'unknown'.
src/controllers/Order.ts(447,60): error TS2345: Argument of type '({ user: { id: string; username: string; email: string; role: string; status: number; phone: string | null; createdAt: Date; updatedAt: Date; password: string; nickname: string | null; avatar: string | null; } | null; items: ({ ...; } & { ...; })[]; addresses: { ...; }[]; } & { ...; }) | null' is not assignable to parameter of type 'OrderWithRelations'.
  Type 'null' is not assignable to type 'OrderWithRelations'.
    Type 'null' is not assignable to type '{ id: string; orderNo: string; userId: string | null; totalAmount: Decimal; status: string; orderType: string; guestName: string | null; guestEmail: string | null; guestPhone: string | null; ... 16 more ...; deliveredAt: Date | null; }'.
src/controllers/Order.ts(507,18): error TS18046: 'error' is of type 'unknown'.
src/controllers/Order.ts(687,25): error TS6133: 'total' is declared but its value is never read.
src/controllers/Order.ts(727,20): error TS18046: 'error' is of type 'unknown'.
src/controllers/Order.ts(805,18): error TS18046: 'error' is of type 'unknown'.
src/controllers/Payment.ts(51,20): error TS18046: 'error' is of type 'unknown'.
src/controllers/Payment.ts(282,16): error TS18046: 'error' is of type 'unknown'.
src/controllers/Payment.ts(312,16): error TS18046: 'error' is of type 'unknown'.
src/controllers/Payment.ts(381,9): error TS2322: Type '{ paymentIntentId: any; }' is not assignable to type 'PaymentWhereUniqueInput'.
  Type '{ paymentIntentId: any; }' is not assignable to type '{ id: string; paymentNo: string; } & { id?: string | undefined; paymentNo?: string | undefined; AND?: PaymentWhereInput | PaymentWhereInput[] | undefined; ... 27 more ...; user?: (Without<...> & UserWhereInput) | ... 2 more ... | undefined; }'.
    Type '{ paymentIntentId: any; }' is missing the following properties from type '{ id: string; paymentNo: string; }': id, paymentNo
src/controllers/Payment.ts(383,11): error TS2322: Type '"EXPIRED"' is not assignable to type 'EnumPaymentStatusFieldUpdateOperationsInput | PaymentStatus | undefined'.
src/controllers/Payment.ts(398,11): error TS2322: Type '"EXPIRED"' is not assignable to type 'OrderPaymentStatus | EnumOrderPaymentStatusFieldUpdateOperationsInput | undefined'.
src/controllers/Payment.ts(434,16): error TS18046: 'error' is of type 'unknown'.
src/controllers/Product.ts(5,1): error TS6133: 'adminMiddleware' is declared but its value is never read.
src/controllers/Product.ts(6,97): error TS6133: 'SortParams' is declared but its value is never read.
src/controllers/Product.ts(6,109): error TS6133: 'PriceRange' is declared but its value is never read.
src/controllers/Product.ts(6,121): error TS6133: 'PaginationParams' is declared but its value is never read.
src/controllers/Product.ts(141,88): error TS7006: Parameter 'tag' implicitly has an 'any' type.
src/controllers/Product.ts(141,114): error TS7006: Parameter 'tag' implicitly has an 'any' type.
src/controllers/Product.ts(652,7): error TS6133: 'includeDisabledCategories' is declared but its value is never read.
src/controllers/Product.ts(656,11): error TS6133: 'includeDisabled' is declared but its value is never read.
src/controllers/Role.ts(9,32): error TS2339: Property 'role' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(65,13): error TS2339: Property 'name' does not exist on type 'unknown'.
src/controllers/Role.ts(65,19): error TS2339: Property 'description' does not exist on type 'unknown'.
src/controllers/Role.ts(68,39): error TS2339: Property 'role' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(84,31): error TS2339: Property 'role' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(114,13): error TS2339: Property 'name' does not exist on type 'unknown'.
src/controllers/Role.ts(114,19): error TS2339: Property 'description' does not exist on type 'unknown'.
src/controllers/Role.ts(114,32): error TS2339: Property 'status' does not exist on type 'unknown'.
src/controllers/Role.ts(117,39): error TS2339: Property 'role' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(135,41): error TS2339: Property 'role' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(152,31): error TS2339: Property 'role' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(186,39): error TS2339: Property 'role' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(203,18): error TS2339: Property 'roleRoutePermission' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(208,18): error TS2339: Property 'userRole' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(213,18): error TS2339: Property 'role' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(239,13): error TS2339: Property 'roleId' does not exist on type 'unknown'.
src/controllers/Role.ts(239,21): error TS2339: Property 'routeIds' does not exist on type 'unknown'.
src/controllers/Role.ts(242,31): error TS2339: Property 'role' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(259,18): error TS2339: Property 'roleRoutePermission' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(270,20): error TS2339: Property 'roleRoutePermission' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(297,13): error TS2339: Property 'userId' does not exist on type 'unknown'.
src/controllers/Role.ts(297,21): error TS2339: Property 'roleIds' does not exist on type 'unknown'.
src/controllers/Role.ts(317,18): error TS2339: Property 'userRole' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Role.ts(328,20): error TS2339: Property 'userRole' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(9,33): error TS2339: Property 'route' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(41,13): error TS2339: Property 'name' does not exist on type 'unknown'.
src/controllers/Route.ts(41,19): error TS2339: Property 'path' does not exist on type 'unknown'.
src/controllers/Route.ts(41,25): error TS2339: Property 'method' does not exist on type 'unknown'.
src/controllers/Route.ts(41,33): error TS2339: Property 'description' does not exist on type 'unknown'.
src/controllers/Route.ts(41,46): error TS2339: Property 'category' does not exist on type 'unknown'.
src/controllers/Route.ts(44,40): error TS2339: Property 'route' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(65,32): error TS2339: Property 'route' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(98,13): error TS2339: Property 'name' does not exist on type 'unknown'.
src/controllers/Route.ts(98,19): error TS2339: Property 'path' does not exist on type 'unknown'.
src/controllers/Route.ts(98,25): error TS2339: Property 'method' does not exist on type 'unknown'.
src/controllers/Route.ts(98,33): error TS2339: Property 'description' does not exist on type 'unknown'.
src/controllers/Route.ts(98,46): error TS2339: Property 'category' does not exist on type 'unknown'.
src/controllers/Route.ts(98,56): error TS2339: Property 'status' does not exist on type 'unknown'.
src/controllers/Route.ts(101,40): error TS2339: Property 'route' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(118,40): error TS2339: Property 'route' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(142,32): error TS2339: Property 'route' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(179,40): error TS2339: Property 'route' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(196,18): error TS2339: Property 'roleRoutePermission' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(201,18): error TS2339: Property 'route' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(230,36): error TS2339: Property 'userRole' does not exist on type 'PrismaClient<PrismaClientOptions, never, DefaultArgs>'.
src/controllers/Route.ts(249,23): error TS7006: Parameter 'userRole' implicitly has an 'any' type.
src/controllers/Route.ts(250,50): error TS7006: Parameter 'permission' implicitly has an 'any' type.
src/controllers/User.ts(52,7): error TS2353: Object literal may only specify known properties, and 'role' does not exist in type '{ id: string; username: string; email: string; }'.
src/controllers/User.ts(96,7): error TS2353: Object literal may only specify known properties, and 'role' does not exist in type '{ id: string; username: string; email: string; }'.
src/jobs/cleanup.ts(65,5): error TS2353: Object literal may only specify known properties, and 'scheduled' does not exist in type 'TaskOptions'.
src/middleware/auth.ts(102,14): error TS2769: No overload matches this call.
  Overload 1 of 5, '(payload: string | object | Buffer<ArrayBufferLike>, secretOrPrivateKey: null, options?: (SignOptions & { algorithm: "none"; }) | undefined): string', gave the following error.
    Argument of type 'string' is not assignable to parameter of type 'null'.
  Overload 2 of 5, '(payload: string | object | Buffer<ArrayBufferLike>, secretOrPrivateKey: Secret | Buffer<ArrayBufferLike> | JsonWebKeyInput | PrivateKeyInput, options?: SignOptions | undefined): string', gave the following error.
    Type 'string' is not assignable to type 'number | StringValue | undefined'.
  Overload 3 of 5, '(payload: string | object | Buffer<ArrayBufferLike>, secretOrPrivateKey: Secret | Buffer<ArrayBufferLike> | JsonWebKeyInput | PrivateKeyInput, callback: SignCallback): void', gave the following error.
    Object literal may only specify known properties, and 'expiresIn' does not exist in type 'SignCallback'.
src/middleware/cors.ts(1,18): error TS7016: Could not find a declaration file for module '@koa/cors'. 'E:/moxton-lotapi/node_modules/@koa/cors/index.js' implicitly has an 'any' type.
  Try `npm i --save-dev @types/koa__cors` if it exists or add a new declaration (.d.ts) file containing `declare module '@koa/cors';`
src/middleware/cors.ts(27,21): error TS7006: Parameter 'ctx' implicitly has an 'any' type.
src/middleware/error.ts(2,20): error TS6133: 'logWarn' is declared but its value is never read.
src/middleware/error.ts(2,29): error TS6133: 'logInfo' is declared but its value is never read.
src/middleware/error.ts(3,1): error TS6192: All imports in import declaration are unused.
src/middleware/error.ts(240,31): error TS6133: 'next' is declared but its value is never read.
src/models/base.ts(54,44): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(62,34): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(75,46): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(92,46): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(121,46): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(139,54): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(152,47): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(169,51): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(189,52): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(228,44): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(241,48): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/base.ts(265,45): error TS2731: Implicit conversion of a 'symbol' to a 'string' will fail at runtime. Consider wrapping this expression in 'String(...)'.
src/models/Cart.ts(1,21): error TS6133: 'PaginationParams' is declared but its value is never read.
src/models/Cart.ts(35,14): error TS2323: Cannot redeclare exported variable 'CartModel'.
src/models/Cart.ts(98,11): error TS2322: Type 'string | null' is not assignable to type 'string | undefined'.
  Type 'null' is not assignable to type 'string | undefined'.
src/models/Cart.ts(99,11): error TS2322: Type 'string | null' is not assignable to type 'string | undefined'.
  Type 'null' is not assignable to type 'string | undefined'.
src/models/Cart.ts(159,9): error TS2322: Type 'string | null' is not assignable to type 'string | undefined'.
  Type 'null' is not assignable to type 'string | undefined'.
src/models/Cart.ts(160,9): error TS2322: Type 'string | null' is not assignable to type 'string | undefined'.
  Type 'null' is not assignable to type 'string | undefined'.
src/models/Cart.ts(479,11): error TS2322: Type 'string | null' is not assignable to type 'string | undefined'.
  Type 'null' is not assignable to type 'string | undefined'.
src/models/Cart.ts(546,10): error TS2323: Cannot redeclare exported variable 'CartModel'.
src/models/Cart.ts(546,10): error TS2484: Export declaration conflicts with exported declaration of 'CartModel'.
src/models/index.ts(5,10): error TS2305: Module '"./Payment"' has no exported member 'default'.
src/models/index.ts(7,10): error TS2305: Module '"./Inquiry"' has no exported member 'default'.
src/models/Inquiry.ts(1,1): error TS6133: 'Context' is declared but its value is never read.
src/models/Inquiry.ts(7,14): error TS2515: Non-abstract class 'InquiryModel' does not implement inherited abstract member modelName from class 'BaseModel<any, any, any>'.
src/models/Inquiry.ts(10,10): error TS2715: Abstract property 'modelName' in class 'BaseModel' cannot be accessed in the constructor.
src/models/Notification.ts(30,9): error TS2552: Cannot find name 'prisma'. Did you mean 'Prisma'?
src/models/Notification.ts(36,9): error TS2552: Cannot find name 'prisma'. Did you mean 'Prisma'?
src/models/Notification.ts(61,28): error TS2552: Cannot find name 'prisma'. Did you mean 'Prisma'?
src/models/Notification.ts(85,13): error TS6133: 'result' is declared but its value is never read.
src/models/Notification.ts(85,28): error TS2552: Cannot find name 'prisma'. Did you mean 'Prisma'?
src/models/Notification.ts(99,28): error TS2552: Cannot find name 'prisma'. Did you mean 'Prisma'?
src/models/Notification.ts(115,28): error TS2552: Cannot find name 'prisma'. Did you mean 'Prisma'?
src/models/Notification.ts(131,28): error TS2552: Cannot find name 'prisma'. Did you mean 'Prisma'?
src/models/Notification.ts(147,28): error TS2552: Cannot find name 'prisma'. Did you mean 'Prisma'?
src/models/Notification.ts(170,27): error TS2552: Cannot find name 'prisma'. Did you mean 'Prisma'?
src/models/Notification.ts(187,9): error TS2552: Cannot find name 'prisma'. Did you mean 'Prisma'?
src/models/Notification.ts(188,9): error TS2304: Cannot find name 'prisma'.
src/models/Notification.ts(189,9): error TS2304: Cannot find name 'prisma'.
src/models/Notification.ts(190,9): error TS2304: Cannot find name 'prisma'.
src/models/Notification.ts(191,9): error TS2304: Cannot find name 'prisma'.
src/models/Notification.ts(209,35): error TS2304: Cannot find name 'prisma'.
src/models/Notification.ts(226,28): error TS2304: Cannot find name 'prisma'.
src/models/Notification.ts(243,34): error TS2304: Cannot find name 'prisma'.
src/models/OfflineOrder.ts(1,10): error TS6133: 'PrismaClient' is declared but its value is never read.
src/models/OfflineOrder.ts(1,38): error TS6133: 'Prisma' is declared but its value is never read.
src/models/OfflineOrder.ts(35,14): error TS2515: Non-abstract class 'OfflineOrderModel' does not implement inherited abstract member modelName from class 'BaseModel<{ message: string | null; id: string; email: string | null; name: string; userId: string | null; status: string; phone: string; createdAt: Date; updatedAt: Date; sessionId: string | null; ... 4 more ...; assignedTo: string | null; }, OfflineOrderCreateInput, OfflineOrderUpdateInput>'.
src/models/OfflineOrder.ts(38,10): error TS2715: Abstract property 'modelName' in class 'BaseModel' cannot be accessed in the constructor.
src/models/OfflineOrder.ts(392,11): error TS2322: Type 'string[]' is not assignable to type 'string'.
src/models/OfflineOrder.ts(816,5): error TS6133: 'newOrder' is declared but its value is never read.
src/models/OfflineOrderHistory.ts(2,1): error TS6133: 'Context' is declared but its value is never read.
src/models/OfflineOrderHistory.ts(7,47): error TS2314: Generic type 'BaseModel<T, CreateData, UpdateData>' requires 3 type argument(s).
src/models/Payment.ts(1,1): error TS6133: 'Context' is declared but its value is never read.
src/models/Payment.ts(6,35): error TS2314: Generic type 'BaseModel<T, CreateData, UpdateData>' requires 3 type argument(s).
src/models/Payment.ts(96,34): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(131,34): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(173,14): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(198,14): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(217,34): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(261,34): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(286,30): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(295,30): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(323,34): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(353,33): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(353,60): error TS7006: Parameter 'tx' implicitly has an 'any' type.
src/models/Payment.ts(387,34): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(421,18): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(446,14): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(447,14): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(448,14): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(449,14): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(450,14): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(451,14): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(455,14): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(460,14): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Payment.ts(490,49): error TS7006: Parameter 'acc' implicitly has an 'any' type.
src/models/Payment.ts(490,54): error TS7006: Parameter 'item' implicitly has an 'any' type.
src/models/Payment.ts(515,34): error TS2339: Property 'prisma' does not exist on type 'PaymentModel'.
src/models/Product.ts(340,16): error TS2790: The operand of a 'delete' operator must be optional.
src/models/Product.ts(344,7): error TS2322: Type 'string[]' is not assignable to type 'string'.
src/models/Product.ts(347,7): error TS2322: Type 'string[] | null' is not assignable to type 'string | null'.
  Type 'string[]' is not assignable to type 'string'.
src/models/Product.ts(353,15): error TS2339: Property 'hasPrice' does not exist on type '{ category: { sort: number; level: number; id: string; name: string; status: number; createdAt: Date; updatedAt: Date; description: string | null; parentId: string | null; parent: { ...; } | null; }; } & { ...; }'.
src/models/Product.ts(353,83): error TS2365: Operator '>' cannot be applied to types 'Decimal' and 'number'.
src/models/Product.ts(657,9): error TS6133: 'sortBy' is declared but its value is never read.
src/models/Product.ts(658,9): error TS6133: 'sortOrder' is declared but its value is never read.
src/routes/auth.ts(9,26): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
src/routes/auth.ts(12,23): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
src/routes/index.ts(17,7): error TS2339: Property 'success' does not exist on type 'ParameterizedContext<any, IRouterParamContext<any, {}>, any>'.
src/routes/index.ts(26,7): error TS2339: Property 'success' does not exist on type 'ParameterizedContext<any, IRouterParamContext<any, {}>, any>'.
src/routes/index.ts(42,8): error TS2769: No overload matches this call.
  Overload 1 of 2, '(...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type 'string' is not assignable to parameter of type 'IMiddleware<any, {}>'.
  Overload 2 of 2, '(path: string | RegExp | string[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type 'RouterComposedMiddleware<DefaultState, DefaultContext>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'context' and 'context' are incompatible.
        Type 'ParameterizedContext<any, IRouterParamContext<any, {}>, any>' is not assignable to type 'ParameterizedContext<DefaultState, DefaultContext & RouterParameterContext<DefaultState, DefaultContext>, any>'.
          Type 'ParameterizedContext<any, IRouterParamContext<any, {}>, any>' is not assignable to type 'RouterParameterContext<DefaultState, DefaultContext>'.
            Types of property 'router' are incompatible.
              Type 'Router<any, {}>' is missing the following properties from type 'Router<DefaultState, DefaultContext>': opts, methods, exclusive, _isPathArray, and 21 more.
src/routes/index.ts(43,8): error TS2769: No overload matches this call.
  Overload 1 of 2, '(...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type 'string' is not assignable to parameter of type 'IMiddleware<any, {}>'.
  Overload 2 of 2, '(path: string | RegExp | string[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type 'RouterComposedMiddleware<DefaultState, DefaultContext>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'context' and 'context' are incompatible.
        Type 'ParameterizedContext<any, IRouterParamContext<any, {}>, any>' is not assignable to type 'ParameterizedContext<DefaultState, DefaultContext & RouterParameterContext<DefaultState, DefaultContext>, any>'.
          Type 'ParameterizedContext<any, IRouterParamContext<any, {}>, any>' is not assignable to type 'RouterParameterContext<DefaultState, DefaultContext>'.
            Types of property 'router' are incompatible.
              Type 'Router<any, {}>' is missing the following properties from type 'Router<DefaultState, DefaultContext>': opts, methods, exclusive, _isPathArray, and 21 more.
src/routes/offline-orders.ts(24,22): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/offline-orders.ts(27,26): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/offline-orders.ts(30,26): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/offline-orders.ts(33,32): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/offline-orders.ts(36,34): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/offline-orders.ts(39,36): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/offline-orders.ts(44,29): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/offline-orders.ts(47,36): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/offline-orders.ts(50,35): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/offline-orders.ts(53,37): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/offline-orders.ts(56,30): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/orders.ts(47,28): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
src/routes/payments.ts(24,3): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
src/routes/products.ts(20,26): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/products.ts(27,25): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/products.ts(30,31): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/products.ts(33,24): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/products.ts(48,29): error TS2769: No overload matches this call.
  Overload 1 of 4, '(name: string, path: string | RegExp, ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
  Overload 2 of 4, '(path: string | RegExp | (string | RegExp)[], ...middleware: IMiddleware<any, {}>[]): Router<any, {}>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'IMiddleware<any, {}>'.
      Types of parameters 'ctx' and 'context' are incompatible.
        Type 'ExtendableContext & { state: any; } & IRouterParamContext<any, {}> & { body: any; response: { body: any; }; }' is missing the following properties from type 'Context': success, fail, error, validationError, and 6 more.
  Overload 3 of 4, '(name: string, path: string | RegExp, middleware: Middleware<DefaultState, Context, any>, routeHandler: IMiddleware<any, Context>): Router<...>', gave the following error.
    Argument of type '(ctx: Context, next: Next) => Promise<void>' is not assignable to parameter of type 'string | RegExp'.
src/routes/upload.ts(4,20): error TS7016: Could not find a declaration file for module '@koa/multer'. 'E:/moxton-lotapi/node_modules/@koa/multer/index.js' implicitly has an 'any' type.
  Try `npm i --save-dev @types/koa__multer` if it exists or add a new declaration (.d.ts) file containing `declare module '@koa/multer';`
src/routes/upload.ts(18,16): error TS6133: 'req' is declared but its value is never read.
src/routes/upload.ts(18,16): error TS7006: Parameter 'req' implicitly has an 'any' type.
src/routes/upload.ts(18,21): error TS7006: Parameter 'file' implicitly has an 'any' type.
src/routes/upload.ts(18,27): error TS7006: Parameter 'cb' implicitly has an 'any' type.
src/services/CacheService.ts(23,24): error TS2769: No overload matches this call.
  Overload 1 of 8, '(path: string, options: RedisOptions): Redis', gave the following error.
    Object literal may only specify known properties, and 'retryDelayOnFailover' does not exist in type 'RedisOptions'.
  Overload 2 of 8, '(port: number, options: RedisOptions): Redis', gave the following error.
    Argument of type 'string' is not assignable to parameter of type 'number'.
  Overload 3 of 8, '(port: number, host: string): Redis', gave the following error.
    Argument of type 'string' is not assignable to parameter of type 'number'.
src/services/CartService.ts(1,36): error TS6133: 'CartModel' is declared but its value is never read.
src/services/CartService.ts(12,28): error TS6133: 'logWarn' is declared but its value is never read.
src/services/CartService.ts(12,37): error TS6133: 'logInfo' is declared but its value is never read.
src/services/CartService.ts(12,46): error TS6133: 'logDebug' is declared but its value is never read.
src/services/CartService.ts(139,13): error TS6133: 'updatedItem' is declared but its value is never read.
src/services/CartService.ts(161,18): error TS18046: 'error' is of type 'unknown'.
src/services/CartService.ts(215,18): error TS18046: 'error' is of type 'unknown'.
src/services/CartService.ts(259,18): error TS18046: 'error' is of type 'unknown'.
src/services/CartService.ts(295,18): error TS18046: 'error' is of type 'unknown'.
src/services/CartService.ts(319,59): error TS18046: 'error' is of type 'unknown'.
src/services/CartService.ts(354,18): error TS18046: 'error' is of type 'unknown'.
src/services/CartService.ts(398,11): error TS6133: 'generateSessionId' is declared but its value is never read.
src/services/GoogleMaps.ts(78,22): error TS18046: 'error' is of type 'unknown'.
src/services/GoogleMaps.ts(79,22): error TS18046: 'error' is of type 'unknown'.
src/services/GoogleMaps.ts(124,12): error TS2352: Conversion of type 'PlaceAutocompleteResponseData' to type '{ predictions: GooglePlaceAutocompletePrediction[]; }' may be a mistake because neither type sufficiently overlaps with the other. If this was intentional, convert the expression to 'unknown' first.
  Types of property 'predictions' are incompatible.
    Type 'PlaceAutocompleteResult[]' is not comparable to type 'GooglePlaceAutocompletePrediction[]'.
      Type 'PlaceAutocompleteResult' is missing the following properties from type 'GooglePlaceAutocompletePrediction': reference, structuredFormatting
src/transformers/OrderTransformer.ts(69,7): error TS2322: Type 'string | null' is not assignable to type 'string | undefined'.
  Type 'null' is not assignable to type 'string | undefined'.
src/utils/addressValidation.ts(182,10): error TS2304: Cannot find name 'cacheId'.

`

### 3) Automated API Test
Command:
`ash
npm run test:api
`
Output:
`	ext

> moxton-lotapi@1.0.0 test:api
> vitest run --config vitest.config.ts


[1m[46m RUN [49m[22m [36mv4.0.18 [39m[90mE:/moxton-lotapi[39m

[90mstdout[2m | tests/api/health.spec.ts
[22m[39m[dotenv@17.2.3] injecting env (23) from .env -- tip: 👥 sync secrets across teammates & machines: https://dotenvx.com/ops

npm.cmd : Sourcemap for "E:/moxton-lotapi/node_modules/node-cron/dist/esm/node-cron.js" points to missing source files
At C:\Users\26249\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1:21 char:16
+ function npm { & npm.cmd @Args }
+                ~~~~~~~~~~~~~~~
    + CategoryInfo          : NotSpecified: (Sourcemap for "...ng source files:String) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
 
[90mstdout[2m | tests/api/health.spec.ts[2m > [22m[2mAPI smoke tests[2m > [22m[2mGET /health returns success payload
[22m[39mGET /health - 200 - 10ms

[90mstdout[2m | tests/api/health.spec.ts[2m > [22m[2mAPI smoke tests[2m > [22m[2mGET /version returns version metadata
[22m[39mGET /version - 200 - 0ms

 [32m✓[39m tests/api/health.spec.ts [2m([22m[2m2 tests[22m[2m)[22m[32m 30[2mms[22m[39m

[2m Test Files [22m [1m[32m1 passed[39m[22m[90m (1)[39m
[2m      Tests [22m [1m[32m2 passed[39m[22m[90m (2)[39m
[2m   Start at [22m 23:31:03
[2m   Duration [22m 653ms[2m (transform 100ms, setup 0ms, import 502ms, tests 30ms, environment 0ms)[22m


`

### 4) Runtime API Verification (curl)
Commands:
- Login with QA identity pool (admin + non-admin, with retry on failed credentials)
- curl requests for all changed endpoints and negative/edge paths
- Legacy route removal check (GET /users)

Output:
`	ext
=== ADMIN_LOGIN_ATTEMPT username=admin password=admin123 ===
ADMIN_LOGIN_RESPONSE={
    "code":  200,
    "message":  "Login successful",
    "data":  {
                 "user":  {
                              "id":  "cmimuic0n0003vff837ohnybf",
                              "username":  "admin",
                              "email":  "admin@moxton.com",
                              "nickname":  null,
                              "phone":  null,
                              "avatar":  null,
                              "role":  "admin",
                              "status":  1,
                              "createdAt":  "2025-12-01T07:46:31.895Z",
                              "updatedAt":  "2025-12-02T03:50:33.068Z"
                          },
                 "token":  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw"
             },
    "timestamp":  "2026-02-26T15:32:16.681Z",
    "success":  true
}
=== USER_LOGIN_ATTEMPT username=testadmin password=test123 ===
USER_LOGIN_ERROR_STATUS=401
USER_LOGIN_ERROR_BODY=
=== USER_LOGIN_ATTEMPT username=testadmin password=test123456 ===
USER_LOGIN_RESPONSE={
    "code":  200,
    "message":  "Login successful",
    "data":  {
                 "user":  {
                              "id":  "cmj0wjk830002vfj87p8u64y6",
                              "username":  "testadmin",
                              "email":  "testadmin@moxton.com",
                              "nickname":  null,
                              "phone":  "13800138002",
                              "avatar":  null,
                              "role":  "user",
                              "status":  1,
                              "createdAt":  "2025-12-11T03:52:14.884Z",
                              "updatedAt":  "2026-02-26T15:02:59.417Z"
                          },
                 "token":  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtajB3ams4MzAwMDJ2Zmo4N3A4dTY0eTYiLCJ1c2VybmFtZSI6InRlc3RhZG1pbiIsImVtYWlsIjoidGVzdGFkbWluQG1veHRvbi5jb20iLCJyb2xlIjoidXNlciIsImlhdCI6MTc3MjExOTkzNywiZXhwIjoxNzcyNzI0NzM3fQ.t_l6W5Mw_V6dhIWsJCWUQ_0KbhfzpmoBZga3tnGC9Gk"
             },
    "timestamp":  "2026-02-26T15:32:17.264Z",
    "success":  true
}
IDENTITY_ADMIN_USERNAME=admin
IDENTITY_ADMIN_PASSWORD_USED=admin123
IDENTITY_USER_USERNAME=testadmin
IDENTITY_USER_PASSWORD_USED=test123456
IDENTITY_ADMIN_ID=cmimuic0n0003vff837ohnybf
IDENTITY_USER_ID=cmj0wjk830002vfj87p8u64y6
DISPOSABLE_USER_RESPONSE={
    "code":  200,
    "message":  "User registered successfully",
    "data":  {
                 "user":  {
                              "id":  "cmm3mgf66000yvfi4tjsyx5wb",
                              "username":  "qa_delete_1772119937",
                              "email":  "qa_delete_1772119937@example.com",
                              "nickname":  null,
                              "phone":  null,
                              "avatar":  null,
                              "role":  "user",
                              "status":  1,
                              "createdAt":  "2026-02-26T15:32:17.742Z",
                              "updatedAt":  "2026-02-26T15:32:17.742Z"
                          },
                 "token":  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtbTNtZ2Y2NjAwMHl2Zmk0dGpzeXg1d2IiLCJ1c2VybmFtZSI6InFhX2RlbGV0ZV8xNzcyMTE5OTM3IiwiZW1haWwiOiJxYV9kZWxldGVfMTc3MjExOTkzN0BleGFtcGxlLmNvbSIsInJvbGUiOiJ1c2VyIiwiaWF0IjoxNzcyMTE5OTM4LCJleHAiOjE3NzI3MjQ3Mzh9.yjqx90mvX0bUI5KbF-GmYCICIEEQQORuM35Y81-azVQ"
             },
    "timestamp":  "2026-02-26T15:32:18.970Z",
    "success":  true
}
=== GET_/auth/admin/users_no_token ===
CMD: curl -sS -i http://127.0.0.1:3033/auth/admin/users?pageNum=1&pageSize=2
HTTP/1.1 401 Unauthorized
X-Request-ID: f64613d22ca24b9f
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 130
Date: Thu, 26 Feb 2026 15:32:18 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 401,
  "message": "No token provided",
  "data": null,
  "timestamp": "2026-02-26T15:32:18.991Z",
  "success": false
}

=== GET_/auth/admin/users_non_admin ===
CMD: curl -sS -i http://127.0.0.1:3033/auth/admin/users?pageNum=1&pageSize=2 -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtajB3ams4MzAwMDJ2Zmo4N3A4dTY0eTYiLCJ1c2VybmFtZSI6InRlc3RhZG1pbiIsImVtYWlsIjoidGVzdGFkbWluQG1veHRvbi5jb20iLCJyb2xlIjoidXNlciIsImlhdCI6MTc3MjExOTkzNywiZXhwIjoxNzcyNzI0NzM3fQ.t_l6W5Mw_V6dhIWsJCWUQ_0KbhfzpmoBZga3tnGC9Gk
HTTP/1.1 403 Forbidden
X-Request-ID: b15d70b191974639
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 146
Date: Thu, 26 Feb 2026 15:32:19 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 403,
  "message": "Administrator privileges required",
  "data": null,
  "timestamp": "2026-02-26T15:32:19.027Z",
  "success": false
}

=== GET_/auth/admin/users_admin_basic ===
CMD: curl -sS -i http://127.0.0.1:3033/auth/admin/users?pageNum=1&pageSize=5 -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw
HTTP/1.1 200 OK
X-Request-ID: a82ded459f644e94
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 2080
Date: Thu, 26 Feb 2026 15:32:20 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 200,
  "message": "Success",
  "data": {
    "list": [
      {
        "id": "cmm3mgf66000yvfi4tjsyx5wb",
        "username": "qa_delete_1772119937",
        "email": "qa_delete_1772119937@example.com",
        "nickname": null,
        "phone": null,
        "avatar": null,
        "role": "user",
        "status": 1,
        "createdAt": "2026-02-26T15:32:17.742Z",
        "updatedAt": "2026-02-26T15:32:17.742Z"
      },
      {
        "id": "cmm3ldne80001vfi4xnaybb4j",
        "username": "qa_delete_1772118128",
        "email": "qa_delete_1772118128@example.com",
        "nickname": null,
        "phone": null,
        "avatar": null,
        "role": "user",
        "status": 1,
        "createdAt": "2026-02-26T15:02:08.816Z",
        "updatedAt": "2026-02-26T15:02:08.816Z"
      },
      {
        "id": "cmm3lcu720000vfi4ps59on7f",
        "username": "qa_delete_1772118090",
        "email": "qa_delete_1772118090@example.com",
        "nickname": null,
        "phone": null,
        "avatar": null,
        "role": "user",
        "status": 1,
        "createdAt": "2026-02-26T15:01:30.974Z",
        "updatedAt": "2026-02-26T15:01:30.974Z"
      },
      {
        "id": "cmm38r5q40000vf4k0192hb9p",
        "username": "waylon",
        "email": "2624949165@qq.com",
        "nickname": "123123",
        "phone": "1231231231",
        "avatar": "12312312",
        "role": "user",
        "status": 1,
        "createdAt": "2026-02-26T09:08:44.093Z",
        "updatedAt": "2026-02-26T15:22:40.478Z"
      },
      {
        "id": "cmm36f1p40000vfyoq87eenmx",
        "username": "qa_fix2_user_202602261603191812",
        "email": "qa_fix2_202602261603191812@example.com",
        "nickname": null,
        "phone": null,
        "avatar": null,
        "role": "user",
        "status": 1,
        "createdAt": "2026-02-26T08:03:19.768Z",
        "updatedAt": "2026-02-26T08:03:19.768Z"
      }
    ],
    "pageNum": 1,
    "pageSize": 5,
    "total": 15,
    "totalPages": 3
  },
  "timestamp": "2026-02-26T15:32:20.340Z",
  "success": true
}

=== GET_/auth/admin/users_admin_filters ===
CMD: curl -sS -i http://127.0.0.1:3033/auth/admin/users?pageNum=1&pageSize=5&keyword=test&status=1&role=user -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw
HTTP/1.1 200 OK
X-Request-ID: 40bf54d77a4d4da0
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 1959
Date: Thu, 26 Feb 2026 15:32:20 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 200,
  "message": "Success",
  "data": {
    "list": [
      {
        "id": "cmj0wjk830002vfj87p8u64y6",
        "username": "testadmin",
        "email": "testadmin@moxton.com",
        "nickname": null,
        "phone": "13800138002",
        "avatar": null,
        "role": "user",
        "status": 1,
        "createdAt": "2025-12-11T03:52:14.884Z",
        "updatedAt": "2026-02-26T15:02:59.417Z"
      },
      {
        "id": "cmio11z140001vf3wqfsm5orf",
        "username": "testuser4",
        "email": "test4@moxton.com",
        "nickname": null,
        "phone": null,
        "avatar": null,
        "role": "user",
        "status": 1,
        "createdAt": "2025-12-02T03:37:32.056Z",
        "updatedAt": "2025-12-02T03:37:32.056Z"
      },
      {
        "id": "cmio11sh50000vf3w2ptztvak",
        "username": "testuser3",
        "email": "test3@moxton.com",
        "nickname": null,
        "phone": null,
        "avatar": null,
        "role": "user",
        "status": 1,
        "createdAt": "2025-12-02T03:37:23.562Z",
        "updatedAt": "2025-12-02T03:37:23.562Z"
      },
      {
        "id": "cmio0uey00000vfckr6stk14q",
        "username": "testuser2",
        "email": "test2@moxton.com",
        "nickname": "Test User 2",
        "phone": null,
        "avatar": null,
        "role": "user",
        "status": 1,
        "createdAt": "2025-12-02T03:31:39.432Z",
        "updatedAt": "2025-12-02T03:31:39.432Z"
      },
      {
        "id": "cmimtwunx0000vff8f57pw7i8",
        "username": "testuser",
        "email": "test@example.com",
        "nickname": null,
        "phone": null,
        "avatar": null,
        "role": "user",
        "status": 1,
        "createdAt": "2025-12-01T07:29:49.629Z",
        "updatedAt": "2025-12-01T07:29:49.629Z"
      }
    ],
    "pageNum": 1,
    "pageSize": 5,
    "total": 5,
    "totalPages": 1
  },
  "timestamp": "2026-02-26T15:32:20.691Z",
  "success": true
}

=== GET_/auth/admin/users/:id_success ===
CMD: curl -sS -i http://127.0.0.1:3033/auth/admin/users/cmj0wjk830002vfj87p8u64y6 -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw
HTTP/1.1 200 OK
X-Request-ID: a3b0dbe357af4855
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 421
Date: Thu, 26 Feb 2026 15:32:21 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 200,
  "message": "Success",
  "data": {
    "id": "cmj0wjk830002vfj87p8u64y6",
    "username": "testadmin",
    "email": "testadmin@moxton.com",
    "nickname": null,
    "phone": "13800138002",
    "avatar": null,
    "role": "user",
    "status": 1,
    "createdAt": "2025-12-11T03:52:14.884Z",
    "updatedAt": "2026-02-26T15:02:59.417Z"
  },
  "timestamp": "2026-02-26T15:32:21.042Z",
  "success": true
}

=== GET_/auth/admin/users/:id_not_found ===
CMD: curl -sS -i http://127.0.0.1:3033/auth/admin/users/not-exists-id-123 -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw
HTTP/1.1 404 Not Found
X-Request-ID: f320d927f5f34af2
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 127
Date: Thu, 26 Feb 2026 15:32:21 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 404,
  "message": "User not found",
  "data": null,
  "timestamp": "2026-02-26T15:32:21.225Z",
  "success": false
}

=== PUT_/auth/admin/users/:id/status_invalid ===
CMD: curl -sS -i -X PUT http://127.0.0.1:3033/auth/admin/users/cmj0wjk830002vfj87p8u64y6/status -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw -H Content-Type: application/json --data-binary @E:\moxton-lotapi\qa-20260226-225136-028-271740-2-status-invalid.json
HTTP/1.1 400 Bad Request
X-Request-ID: db7396fdbf064fa6
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 182
Date: Thu, 26 Feb 2026 15:32:21 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 400,
  "message": "Validation Error",
  "data": {
    "errors": [
      "Status must be 0 or 1"
    ]
  },
  "timestamp": "2026-02-26T15:32:21.263Z",
  "success": false
}

=== PUT_/auth/admin/users/:id/status_self_protect ===
CMD: curl -sS -i -X PUT http://127.0.0.1:3033/auth/admin/users/cmimuic0n0003vff837ohnybf/status -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw -H Content-Type: application/json --data-binary @E:\moxton-lotapi\qa-20260226-225136-028-271740-2-status-disable.json
HTTP/1.1 403 Forbidden
X-Request-ID: 3ee6f698398240ed
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 142
Date: Thu, 26 Feb 2026 15:32:21 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 403,
  "message": "Cannot change your own status",
  "data": null,
  "timestamp": "2026-02-26T15:32:21.298Z",
  "success": false
}

=== PUT_/auth/admin/users/:id/status_success_disable ===
CMD: curl -sS -i -X PUT http://127.0.0.1:3033/auth/admin/users/cmj0wjk830002vfj87p8u64y6/status -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw -H Content-Type: application/json --data-binary @E:\moxton-lotapi\qa-20260226-225136-028-271740-2-status-disable.json
HTTP/1.1 200 OK
X-Request-ID: a40f505bd9764c83
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 446
Date: Thu, 26 Feb 2026 15:32:23 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 200,
  "message": "User status updated successfully",
  "data": {
    "id": "cmj0wjk830002vfj87p8u64y6",
    "username": "testadmin",
    "email": "testadmin@moxton.com",
    "nickname": null,
    "phone": "13800138002",
    "avatar": null,
    "role": "user",
    "status": 0,
    "createdAt": "2025-12-11T03:52:14.884Z",
    "updatedAt": "2026-02-26T15:32:21.615Z"
  },
  "timestamp": "2026-02-26T15:32:23.034Z",
  "success": true
}

=== PUT_/auth/admin/users/:id/status_success_enable ===
CMD: curl -sS -i -X PUT http://127.0.0.1:3033/auth/admin/users/cmj0wjk830002vfj87p8u64y6/status -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw -H Content-Type: application/json --data-binary @E:\moxton-lotapi\qa-20260226-225136-028-271740-2-status-enable.json
HTTP/1.1 200 OK
X-Request-ID: bc4352a6d85c4522
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 446
Date: Thu, 26 Feb 2026 15:32:24 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 200,
  "message": "User status updated successfully",
  "data": {
    "id": "cmj0wjk830002vfj87p8u64y6",
    "username": "testadmin",
    "email": "testadmin@moxton.com",
    "nickname": null,
    "phone": "13800138002",
    "avatar": null,
    "role": "user",
    "status": 1,
    "createdAt": "2025-12-11T03:52:14.884Z",
    "updatedAt": "2026-02-26T15:32:23.230Z"
  },
  "timestamp": "2026-02-26T15:32:24.508Z",
  "success": true
}

=== PUT_/auth/admin/users/:id/role_invalid ===
CMD: curl -sS -i -X PUT http://127.0.0.1:3033/auth/admin/users/cmj0wjk830002vfj87p8u64y6/role -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw -H Content-Type: application/json --data-binary @E:\moxton-lotapi\qa-20260226-225136-028-271740-2-role-invalid.json
HTTP/1.1 400 Bad Request
X-Request-ID: bca82edc3e0a4c18
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 195
Date: Thu, 26 Feb 2026 15:32:24 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 400,
  "message": "Validation Error",
  "data": {
    "errors": [
      "Role must be \"user\" or \"admin\""
    ]
  },
  "timestamp": "2026-02-26T15:32:24.549Z",
  "success": false
}

=== PUT_/auth/admin/users/:id/role_self_protect ===
CMD: curl -sS -i -X PUT http://127.0.0.1:3033/auth/admin/users/cmimuic0n0003vff837ohnybf/role -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw -H Content-Type: application/json --data-binary @E:\moxton-lotapi\qa-20260226-225136-028-271740-2-role-user.json
HTTP/1.1 403 Forbidden
X-Request-ID: b9f725fd5445423e
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 140
Date: Thu, 26 Feb 2026 15:32:24 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 403,
  "message": "Cannot change your own role",
  "data": null,
  "timestamp": "2026-02-26T15:32:24.585Z",
  "success": false
}

=== PUT_/auth/admin/users/:id/role_success_admin ===
CMD: curl -sS -i -X PUT http://127.0.0.1:3033/auth/admin/users/cmj0wjk830002vfj87p8u64y6/role -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw -H Content-Type: application/json --data-binary @E:\moxton-lotapi\qa-20260226-225136-028-271740-2-role-admin.json
HTTP/1.1 200 OK
X-Request-ID: b66a53fc767c4e2c
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 445
Date: Thu, 26 Feb 2026 15:32:25 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 200,
  "message": "User role updated successfully",
  "data": {
    "id": "cmj0wjk830002vfj87p8u64y6",
    "username": "testadmin",
    "email": "testadmin@moxton.com",
    "nickname": null,
    "phone": "13800138002",
    "avatar": null,
    "role": "admin",
    "status": 1,
    "createdAt": "2025-12-11T03:52:14.884Z",
    "updatedAt": "2026-02-26T15:32:25.045Z"
  },
  "timestamp": "2026-02-26T15:32:25.895Z",
  "success": true
}

=== PUT_/auth/admin/users/:id/role_success_revert_user ===
CMD: curl -sS -i -X PUT http://127.0.0.1:3033/auth/admin/users/cmj0wjk830002vfj87p8u64y6/role -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw -H Content-Type: application/json --data-binary @E:\moxton-lotapi\qa-20260226-225136-028-271740-2-role-user.json
HTTP/1.1 200 OK
X-Request-ID: f6278b7d378c4022
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 444
Date: Thu, 26 Feb 2026 15:32:26 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 200,
  "message": "User role updated successfully",
  "data": {
    "id": "cmj0wjk830002vfj87p8u64y6",
    "username": "testadmin",
    "email": "testadmin@moxton.com",
    "nickname": null,
    "phone": "13800138002",
    "avatar": null,
    "role": "user",
    "status": 1,
    "createdAt": "2025-12-11T03:52:14.884Z",
    "updatedAt": "2026-02-26T15:32:26.079Z"
  },
  "timestamp": "2026-02-26T15:32:26.788Z",
  "success": true
}

=== DELETE_/auth/admin/users/:id_self_protect ===
CMD: curl -sS -i -X DELETE http://127.0.0.1:3033/auth/admin/users/cmimuic0n0003vff837ohnybf -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw
HTTP/1.1 403 Forbidden
X-Request-ID: 490a43a404a540f5
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 143
Date: Thu, 26 Feb 2026 15:32:26 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 403,
  "message": "Cannot delete your own account",
  "data": null,
  "timestamp": "2026-02-26T15:32:26.828Z",
  "success": false
}

=== DELETE_/auth/admin/users/:id_success_disposable ===
CMD: curl -sS -i -X DELETE http://127.0.0.1:3033/auth/admin/users/cmm3mgf66000yvfi4tjsyx5wb -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw
HTTP/1.1 200 OK
X-Request-ID: 1af4e5762ffa45b5
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 137
Date: Thu, 26 Feb 2026 15:32:27 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 200,
  "message": "User deleted successfully",
  "data": null,
  "timestamp": "2026-02-26T15:32:27.711Z",
  "success": true
}

=== GET_/users_old_route_removed ===
CMD: curl -sS -i http://127.0.0.1:3033/users -H Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6ImNtaW11aWMwbjAwMDN2ZmY4MzdvaG55YmYiLCJ1c2VybmFtZSI6ImFkbWluIiwiZW1haWwiOiJhZG1pbkBtb3h0b24uY29tIiwicm9sZSI6ImFkbWluIiwiaWF0IjoxNzcyMTE5OTM2LCJleHAiOjE3NzI3MjQ3MzZ9.RsaOUXMMdpEQq2ir_QNgenrwbKj1jwpkoYs5Eia-nZw
HTTP/1.1 404 Not Found
X-Request-ID: 25a6a03682e34353
Vary: Origin
Access-Control-Allow-Origin: 
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: *
Content-Security-Policy: default-src 'self';base-uri 'self';font-src 'self' https: data:;form-action 'self';frame-ancestors 'self';img-src 'self' data:;object-src 'none';script-src 'self';script-src-attr 'none';style-src 'self' https: 'unsafe-inline';upgrade-insecure-requests
Cross-Origin-Opener-Policy: same-origin-allow-popups
Cross-Origin-Resource-Policy: cross-origin
Origin-Agent-Cluster: ?1
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-DNS-Prefetch-Control: off
X-Download-Options: noopen
X-Frame-Options: SAMEORIGIN
X-Permitted-Cross-Domain-Policies: none
X-XSS-Protection: 0
Content-Type: application/json; charset=utf-8
Content-Length: 135
Date: Thu, 26 Feb 2026 15:32:27 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{
  "code": 404,
  "message": "API endpoint not found",
  "data": null,
  "timestamp": "2026-02-26T15:32:27.745Z",
  "success": false
}

RUNTIME_LOG=E:\moxton-lotapi\qa-20260226-225136-028-271740-2-runtime.log

`
[/ROUTE]
