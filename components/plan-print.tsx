import { type Client, type ClientPlan, type Exercise } from "@/lib/coach-data";
import { groupExerciseRows } from "@/lib/supersets";
import { CoachBrand } from "@/components/coach-brand";

type PlanPrintProps = {
  client: Client;
  plan: ClientPlan;
  exercises: Exercise[];
  elementId?: string;
};

export function PlanPrint({ client, plan, exercises, elementId }: PlanPrintProps) {
  const exerciseById = new Map(exercises.map((exercise) => [exercise.id, exercise]));
  const hasNutrition = plan.nutritionMeals.some(
    (meal) => meal.foods.trim() || meal.notes.trim(),
  );
  const supplements = plan.supplementItems ?? [];
  const medications = plan.medicationItems ?? [];

  return (
    <section id={elementId} className="print-shell" aria-hidden="true">
      <CoachBrand />
      <h2 className="print-plan-title">{plan.title}</h2>

      <div className="print-client">
        <div><span>ورزشکار</span><strong>{client.name}</strong></div>
        <div><span>هدف</span><strong>{client.goal || "—"}</strong></div>
        <div><span>تماس</span><strong>{client.phone || "—"}</strong></div>
      </div>

      {plan.workoutDays.map((day) => (
        <article className="print-day" key={day.id}>
          <div className="print-day-title">
            <div>
              <p>{day.title}</p>
              <h2>{day.focus || "جلسه تمرینی"}</h2>
            </div>
            <span>{day.exercises.length} حرکت</span>
          </div>
          <div className="print-exercises">
            {groupExerciseRows(day.exercises).map((unit, unitIndex) => {
              const renderedRows = unit.items.map((item, pairIndex) => {
                const exercise = exerciseById.get(item.exerciseId);
                if (!exercise) return null;
                const index = day.exercises.findIndex(
                  (candidate) => candidate.rowId === item.rowId,
                );
                return (
                  <div className="print-exercise" key={item.rowId}>
                    <img src={exercise.image} alt="" />
                    <div className="print-exercise-copy">
                      <p className="print-index">
                        {String(index + 1).padStart(2, "0")}
                        {unit.type === "superset" ? ` · ${pairIndex === 0 ? "A" : "B"}` : ""}
                      </p>
                      <h3>{item.nameFa ?? exercise.nameFa}</h3>
                      <small>{item.nameEn ?? exercise.nameEn}</small>
                      {item.notes && <p className="print-note">{item.notes}</p>}
                    </div>
                    <dl>
                      <div><dt>ست</dt><dd>{item.sets}</dd></div>
                      <div><dt>تکرار</dt><dd>{item.reps}</dd></div>
                      <div><dt>استراحت</dt><dd>{item.rest}</dd></div>
                      <div><dt>تکنیک</dt><dd>{item.technique}</dd></div>
                    </dl>
                  </div>
                );
              });

              if (unit.type === "superset") {
                return (
                  <section className="print-superset-group" key={unit.id}>
                    <div className="print-superset-title">
                      <strong>سوپرست {String(unitIndex + 1).padStart(2, "0")}</strong>
                      <span>اجرای A سپس B بدون استراحت</span>
                    </div>
                    {renderedRows.map((renderedRow, pairIndex) => (
                      <section className="print-exercise-unit print-superset-member" key={unit.items[pairIndex].rowId}>
                        {renderedRow}
                      </section>
                    ))}
                  </section>
                );
              }

              return (
                <section className="print-exercise-unit" key={unit.id}>
                  {renderedRows[0]}
                </section>
              );
            })}
          </div>
        </article>
      ))}

      {hasNutrition && (
        <article className="print-day print-nutrition">
          <div className="print-day-title">
            <div>
              <p>تغذیه</p>
              <h2>برنامه غذایی روزانه</h2>
            </div>
            <span>{plan.nutritionMeals.length} وعده</span>
          </div>
          <div className="print-macros">
            <span>کالری: {plan.nutritionGoals.calories || "—"}</span>
            <span>پروتئین: {plan.nutritionGoals.protein || "—"}</span>
            <span>کربوهیدرات: {plan.nutritionGoals.carbs || "—"}</span>
            <span>چربی: {plan.nutritionGoals.fat || "—"}</span>
          </div>
          {plan.nutritionMeals.map((meal) => (
            <div className="print-meal" key={meal.id}>
              <div>
                <h3>{meal.title}</h3>
                <span>{meal.time}</span>
              </div>
              <p>{meal.foods || "—"}</p>
              {meal.notes && <small>{meal.notes}</small>}
            </div>
          ))}
        </article>
      )}

      {supplements.length > 0 && (
        <article className="print-day print-supplements">
          <div className="print-day-title">
            <div><p>مکمل و ویتامین</p><h2>برنامه مکمل روزانه</h2></div>
            <span>{supplements.length} مورد</span>
          </div>
          {supplements.map((item, index) => (
            <div className="print-supplement" key={item.id}>
              <b>{index + 1}</b>
              <div><h3>{item.name}</h3>{item.notes && <small>{item.notes}</small>}</div>
              <dl><div><dt>مقدار</dt><dd>{item.dose || "—"}</dd></div><div><dt>زمان</dt><dd>{item.timing || "—"}</dd></div><div><dt>دفعات</dt><dd>{item.frequency || "—"}</dd></div></dl>
            </div>
          ))}
        </article>
      )}

      {medications.length > 0 && (
        <article className="print-day print-supplements">
          <div className="print-day-title"><div><p>دارو و PCT</p><h2>برنامه دارویی دوره</h2></div><span>{medications.length} مورد</span></div>
          {medications.map((item,index)=><div className="print-supplement" key={item.id}><b>{index+1}</b><div><h3>{item.name}</h3><small>{item.group==="pct"?"پاک‌سازی و PCT":"داروی بدنسازی"} · هفته {item.startWeek||"—"} تا {item.endWeek||"—"}</small>{item.notes&&<small>{item.notes}</small>}</div><dl><div><dt>دوز</dt><dd>{item.dose||"—"}</dd></div><div><dt>زمان</dt><dd>{item.timing||"—"}</dd></div><div><dt>دفعات</dt><dd>{item.frequency||"—"}</dd></div></dl></div>)}
        </article>
      )}

      <footer className="print-footer">
        <span>ARMIN SORKHEI · PERSONAL COACHING</span>
        <span>Consistency builds power.</span>
      </footer>
    </section>
  );
}
